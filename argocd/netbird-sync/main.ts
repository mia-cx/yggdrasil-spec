// Hourly Hecate -> NetBird permission sync. Reads each active Hecate user's
// JWT groups claim via the Authentik scope-mapping test (same code path as
// sign-in), diffs their jwt-issued NetBird auto_groups, and applies updates.
// Then the same for TV peers: a TV's Hecate service account links an owner
// and a NetBird peer id, and the peer gets owner-groups ∩ TV-allowlist.
// Emails once on failure start and once on recovery; run state lives in a
// ConfigMap that is intentionally not in Git.
import { readFileSync } from "node:fs";
import {
  alertTransition,
  decodeDexUserId,
  planPeerUpdates,
  planUserUpdates,
  type NbGroup,
  type NbPeer,
  type NbUser,
  type TvLink,
} from "./lib.ts";
import { sendMail } from "./smtp.ts";

const REQUEST_TIMEOUT_MS = 30_000;

const requireEnv = (name: string): string => {
  const value = process.env[name];
  if (!value) throw new Error(`missing env ${name}`);
  return value;
};

const env = {
  netbirdApi: requireEnv("NETBIRD_API_URL").replace(/\/$/, ""),
  netbirdToken: requireEnv("NETBIRD_TOKEN"),
  netbirdIdpName: process.env.NETBIRD_IDP_NAME ?? "Hecate",
  authentikUrl: requireEnv("AUTHENTIK_URL").replace(/\/$/, ""),
  authentikToken: requireEnv("AUTHENTIK_TOKEN"),
  authentikMappingName: requireEnv("AUTHENTIK_MAPPING_NAME"),
  smtpHost: requireEnv("SMTP_HOST"),
  smtpPort: parseInt(requireEnv("SMTP_PORT"), 10),
  smtpUser: requireEnv("SMTP_USER"),
  smtpPassword: requireEnv("SMTP_PASSWORD"),
  alertFrom: process.env.ALERT_FROM ?? "NetBird sync <noreply@mia.cx>",
  alertTo: requireEnv("ALERT_TO"),
  stateConfigMap: process.env.STATE_CONFIGMAP ?? "netbird-sync-state",
  dryRun: process.env.DRY_RUN === "true",
};

const fetchJson = async (
  url: string,
  token: string,
  scheme: "Token" | "Bearer",
  init?: { method?: string; body?: unknown },
): Promise<unknown> => {
  const res = await fetch(url, {
    method: init?.method ?? "GET",
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    headers: {
      Authorization: `${scheme} ${token}`,
      ...(init?.body === undefined
        ? {}
        : { "Content-Type": "application/json" }),
    },
    ...(init?.body === undefined ? {} : { body: JSON.stringify(init.body) }),
  });
  if (!res.ok)
    throw new Error(`${init?.method ?? "GET"} ${url}: HTTP ${res.status}`);
  return res.json();
};

// --- Authentik -------------------------------------------------------------

interface AkUser {
  pk: number;
  uid: string;
  username: string;
  is_active: boolean;
  /** internal | external | service_account | internal_service_account */
  type: string;
  attributes: Record<string, unknown>;
}

const fetchAllAuthentikUsers = async (): Promise<AkUser[]> => {
  const users: AkUser[] = [];
  let url: string | null =
    `${env.authentikUrl}/api/v3/core/users/?page_size=100&include_groups=false`;
  while (url) {
    const page = (await fetchJson(url, env.authentikToken, "Bearer")) as {
      results: AkUser[];
      pagination: { next: number };
    };
    users.push(...page.results);
    url = page.pagination.next
      ? `${env.authentikUrl}/api/v3/core/users/?page=${page.pagination.next}&page_size=100&include_groups=false`
      : null;
  }
  return users;
};

interface MappingTestResult {
  successful: boolean;
  result: string;
}

const claimGroupsForUser = async (
  mappingPk: string,
  userPk: number,
): Promise<string[]> => {
  const res = (await fetchJson(
    `${env.authentikUrl}/api/v3/propertymappings/all/${mappingPk}/test/`,
    env.authentikToken,
    "Bearer",
    { method: "POST", body: { user: userPk } },
  )) as MappingTestResult;
  if (!res.successful)
    throw new Error(
      `scope-mapping test failed for Authentik user pk ${userPk}`,
    );
  const parsed = JSON.parse(res.result) as { groups?: string[] };
  return parsed.groups ?? [];
};

// --- Kubernetes state --------------------------------------------------------

const SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount";

const k8sState = async (
  op: "get" | "set",
  failing?: boolean,
): Promise<boolean> => {
  let token: string;
  let namespace: string;
  try {
    token = readFileSync(`${SA_DIR}/token`, "utf8").trim();
    namespace = readFileSync(`${SA_DIR}/namespace`, "utf8").trim();
  } catch {
    console.warn("no service-account files; skipping alert state");
    return false;
  }
  const base = `https://kubernetes.default.svc/api/v1/namespaces/${namespace}/configmaps`;
  const name = env.stateConfigMap;
  const headers = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };

  if (op === "get") {
    const res = await fetch(`${base}/${name}`, {
      headers,
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    if (res.status === 404) return false;
    if (!res.ok) throw new Error(`read state ConfigMap: HTTP ${res.status}`);
    const cm = (await res.json()) as { data?: { failing?: string } };
    return cm.data?.failing === "true";
  }

  // Merge-patch touches only the one key; 404 means first run, so create it.
  let res = await fetch(`${base}/${name}`, {
    method: "PATCH",
    headers: { ...headers, "Content-Type": "application/merge-patch+json" },
    body: JSON.stringify({ data: { failing: String(failing) } }),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  if (res.status === 404)
    res = await fetch(base, {
      method: "POST",
      headers,
      body: JSON.stringify({
        apiVersion: "v1",
        kind: "ConfigMap",
        metadata: { name },
        data: { failing: String(failing) },
      }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
  if (!res.ok) throw new Error(`write state ConfigMap: HTTP ${res.status}`);
  return failing!;
};

const alert = async (failing: boolean, errorText: string): Promise<void> => {
  const wasFailing = await k8sState("get");
  const transition = alertTransition(wasFailing, failing);
  if (!transition) return;
  await sendMail({
    host: env.smtpHost,
    port: env.smtpPort,
    user: env.smtpUser,
    password: env.smtpPassword,
    from: env.alertFrom,
    to: env.alertTo,
    subject:
      transition === "failing"
        ? "NetBird permission sync failing"
        : "NetBird permission sync recovered",
    text:
      transition === "failing"
        ? `The hourly Hecate-to-NetBird permission sync failed:\n\n${errorText}\n`
        : "The hourly Hecate-to-NetBird permission sync is healthy again.\n",
  });
  // Record the new state only after the send succeeded.
  await k8sState("set", failing);
};

// --- main -------------------------------------------------------------------

const run = async (): Promise<void> => {
  const nbGet = (path: string) =>
    fetchJson(`${env.netbirdApi}${path}`, env.netbirdToken, "Token");

  const idps = (await nbGet("/identity-providers")) as {
    id: string;
    name: string;
  }[];
  const hecateIdp = idps.find((i) => i.name === env.netbirdIdpName);
  if (!hecateIdp)
    throw new Error(`IdP named "${env.netbirdIdpName}" not found`);

  const users = (await nbGet("/users")) as NbUser[];
  const groups = (await nbGet("/groups")) as NbGroup[];

  const akUsers = await fetchAllAuthentikUsers();
  if (akUsers.length === 0) throw new Error("Authentik returned zero users");
  const activeByUid = new Map(
    akUsers.filter((u) => u.is_active).map((u) => [u.uid, u.pk]),
  );

  const mappings = (await fetchJson(
    `${env.authentikUrl}/api/v3/propertymappings/provider/scope/?name=${encodeURIComponent(env.authentikMappingName)}`,
    env.authentikToken,
    "Bearer",
  )) as { results: { pk: string; name: string }[] };
  const mapping = mappings.results.find(
    (m) => m.name === env.authentikMappingName,
  );
  if (!mapping)
    throw new Error(`scope mapping "${env.authentikMappingName}" not found`);

  const permissions = new Map<string, readonly string[]>();
  // Claim lookups are memoized by pk: a TV owner who's also a NetBird user
  // is evaluated once, and owners who never signed in still get evaluated.
  const claimCache = new Map<number, Promise<string[]>>();
  const claimsFor = (pk: number): Promise<string[]> => {
    let p = claimCache.get(pk);
    if (!p) claimCache.set(pk, (p = claimGroupsForUser(mapping.pk, pk)));
    return p;
  };
  for (const u of users) {
    if (u.idp_id !== hecateIdp.id) continue;
    // Undecodable Hecate-idp ids fail the run (see lib.ts).
    const sub = decodeDexUserId(u.id).sub;
    const akPk = activeByUid.get(sub);
    if (akPk === undefined) continue; // deleted or inactive in Hecate
    permissions.set(sub, await claimsFor(akPk));
  }

  // The mapping tests took seconds; another caller may have edited
  // auto_groups meanwhile. Re-fetch and plan on the fresh snapshot, filtered
  // to ids seen above so a user who first signed in mid-run isn't treated
  // as deleted and stripped.
  const freshUsers = (await nbGet("/users")) as NbUser[];
  const seenIds = new Set(users.map((u) => u.id));
  const plan = planUserUpdates({
    users: freshUsers.filter((u) => seenIds.has(u.id)),
    groups,
    hecateIdpId: hecateIdp.id,
    permissions,
  });

  for (const missing of plan.missingGroups)
    console.warn(`claim group "${missing}" has no NetBird group; skipped`);

  for (const upd of plan.updates) {
    const tag = upd.userId.slice(0, 8);
    console.log(
      `${tag}: ${upd.added.map((n) => `+${n}`).join(" ") || "(no adds)"} ` +
        `${upd.removed.map((n) => `-${n}`).join(" ") || "(no removals)"}`,
    );
  }

  if (env.dryRun)
    console.log(`DRY_RUN: ${plan.updates.length} user update(s) not applied`);
  else {
    const byId = new Map(freshUsers.map((u) => [u.id, u]));
    for (const upd of plan.updates) {
      const user = byId.get(upd.userId)!;
      const res = await fetch(`${env.netbirdApi}/users/${upd.userId}`, {
        method: "PUT",
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
        headers: {
          Authorization: `Token ${env.netbirdToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          role: user.role,
          auto_groups: upd.autoGroups,
          is_blocked: user.is_blocked ?? false,
        }),
      });
      if (!res.ok)
        throw new Error(
          `PUT user ${upd.userId.slice(0, 8)}: HTTP ${res.status}`,
        );
    }
  }

  // --- TV / peer groups -----------------------------------------------------
  // A TV is an Authentik service account carrying two attributes: its owner's
  // username and its NetBird peer id. The peer earns owner-groups ∩ the TV's
  // own claim groups (its allowlist); jwt groups on peers come only from
  // links, so anything else on a non-user peer gets stripped.
  const TV_OWNER_ATTR = "netbird_tv_owner";
  const TV_PEER_ATTR = "netbird_peer_id";

  const tvLinks: TvLink[] = [];
  // Owner must be a real person (internal/external). A service account —
  // including the TV itself — as owner yields no ownerGroups and fails the
  // run; a missing owner is a warning (deleted owner is legit revocation).
  const linkProblems: string[] = [];
  for (const ak of akUsers) {
    const ownerName = ak.attributes?.[TV_OWNER_ATTR];
    if (typeof ownerName !== "string" || ownerName === "") continue;
    if (ak.type !== "service_account") {
      linkProblems.push(
        `tv ${ak.username}: not a service account (${ak.type})`,
      );
      continue;
    }
    const peerId = ak.attributes?.[TV_PEER_ATTR];
    if (typeof peerId !== "string" || peerId === "") {
      console.log(`tv ${ak.username}: not linked yet`);
      continue;
    }
    const allowlist = ak.is_active ? await claimsFor(ak.pk) : [];
    const owner = akUsers.find((u) => u.username === ownerName);
    let ownerGroups: readonly string[] = [];
    if (!owner) {
      console.warn(`tv ${ak.username}: owner "${ownerName}" not found`);
    } else if (owner.type !== "internal" && owner.type !== "external") {
      linkProblems.push(
        `tv ${ak.username}: owner "${ownerName}" is not a person (${owner.type})`,
      );
    } else if (owner.is_active) {
      ownerGroups = await claimsFor(owner.pk);
    }
    tvLinks.push({ tv: ak.username, peerId, ownerGroups, allowlist });
  }

  const peers = (await nbGet("/peers")) as NbPeer[];
  const peerPlan = planPeerUpdates({ peers, groups, tvLinks });

  for (const missing of peerPlan.missingGroups)
    console.warn(`claim group "${missing}" has no NetBird group; skipped`);

  for (const change of peerPlan.changes) {
    const label = change.tv
      ? `tv ${change.tv} (peer ${change.peerName})`
      : `peer ${change.peerName} (unlinked)`;
    console.log(
      `${label}: ${change.added.map((n) => `+${n}`).join(" ") || "(no adds)"} ` +
        `${change.removed.map((n) => `-${n}`).join(" ") || "(no removals)"}`,
    );
  }
  if (plan.updates.length === 0 && peerPlan.changes.length === 0)
    console.log("no changes");

  if (env.dryRun)
    console.log(
      `DRY_RUN: ${peerPlan.groupEdits.length} peer group edit(s) not applied`,
    );
  else {
    // PUT /groups replaces peers AND resources wholesale; re-read right
    // before the write so concurrent changes (and resources) survive.
    const applyGroupEdit = async (
      groupId: string,
      mutate: (ids: Set<string>) => void,
    ): Promise<void> => {
      const fresh = (await nbGet(`/groups/${groupId}`)) as {
        name: string;
        peers?: ({ id: string } | string)[];
        resources?: { id: string; type: string }[];
      };
      const nextPeerIds = new Set(
        (fresh.peers ?? []).map((p) => (typeof p === "string" ? p : p.id)),
      );
      mutate(nextPeerIds);
      const res = await fetch(`${env.netbirdApi}/groups/${groupId}`, {
        method: "PUT",
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
        headers: {
          Authorization: `Token ${env.netbirdToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: fresh.name,
          peers: [...nextPeerIds].sort(),
          resources: fresh.resources ?? [],
        }),
      });
      if (!res.ok) throw new Error(`PUT group ${groupId}: HTTP ${res.status}`);
    };
    // Removals before additions: a run that dies midway leaves peers with
    // less access, never more. Every removal is attempted even if one group
    // fails, so one broken group can't shield other TVs' revocations.
    const removalErrors: string[] = [];
    for (const edit of peerPlan.groupEdits) {
      if (edit.remove.length === 0) continue;
      await applyGroupEdit(edit.groupId, (ids) => {
        for (const id of edit.remove) ids.delete(id);
      }).catch((err: unknown) =>
        removalErrors.push(err instanceof Error ? err.message : String(err)),
      );
    }
    if (removalErrors.length > 0) throw new Error(removalErrors.join("; "));
    for (const edit of peerPlan.groupEdits) {
      if (edit.add.length === 0) continue;
      await applyGroupEdit(edit.groupId, (ids) => {
        for (const id of edit.add) ids.add(id);
      });
    }
  }

  // Everything applicable is already applied; a TV misconfig must fail the
  // run (and the alert) without ever blocking user revocations.
  const problems = [...linkProblems, ...peerPlan.problems];
  if (problems.length > 0) throw new Error(problems.join("; "));
};

const main = async (): Promise<void> => {
  try {
    await run();
    await alert(false, "");
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`sync failed: ${message}`);
    try {
      await alert(true, message);
    } catch (alertErr) {
      console.error(`alert failed too: ${alertErr}`);
    }
    process.exitCode = 1;
  }
};

// No top-level await: this file may be treated as CJS (no package.json in
// the mounted ConfigMap). main() never rejects; it sets exitCode on failure.
void main();
