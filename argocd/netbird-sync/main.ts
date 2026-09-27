// Hourly Hecate -> NetBird permission sync. Reads each active Hecate user's
// JWT groups claim via the Authentik scope-mapping test (same code path as
// sign-in), diffs their jwt-issued NetBird auto_groups, and applies updates.
// Emails once on failure start and once on recovery; run state lives in a
// ConfigMap that is intentionally not in Git.
import { readFileSync } from "node:fs";
import {
  alertTransition,
  decodeDexUserId,
  planUserUpdates,
  type NbGroup,
  type NbUser,
} from "./lib.ts";
import { sendMail } from "./smtp.ts";

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
  is_active: boolean;
}

const fetchAllAuthentikUsers = async (): Promise<AkUser[]> => {
  const users: AkUser[] = [];
  let url: string | null =
    `${env.authentikUrl}/api/v3/core/users/?page_size=100`;
  while (url) {
    const page = (await fetchJson(url, env.authentikToken, "Bearer")) as {
      results: AkUser[];
      pagination: { next: number };
    };
    users.push(...page.results);
    url = page.pagination.next
      ? `${env.authentikUrl}/api/v3/core/users/?page=${page.pagination.next}&page_size=100`
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
    const res = await fetch(`${base}/${name}`, { headers });
    if (res.status === 404) return false;
    if (!res.ok) throw new Error(`read state ConfigMap: HTTP ${res.status}`);
    const cm = (await res.json()) as { data?: { failing?: string } };
    return cm.data?.failing === "true";
  }

  const body = JSON.stringify({
    apiVersion: "v1",
    kind: "ConfigMap",
    metadata: { name },
    data: { failing: String(failing) },
  });
  let res = await fetch(`${base}/${name}`, {
    method: "PUT",
    headers,
    body,
  });
  if (res.status === 404)
    res = await fetch(base, { method: "POST", headers, body });
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
  for (const u of users) {
    if (u.idp_id !== hecateIdp.id) continue;
    // Undecodable Hecate-idp ids fail the run (see lib.ts).
    const sub = decodeDexUserId(u.id).sub;
    const akPk = activeByUid.get(sub);
    if (akPk === undefined) continue; // deleted or inactive in Hecate
    permissions.set(sub, await claimGroupsForUser(mapping.pk, akPk));
  }

  const plan = planUserUpdates({
    users,
    groups,
    hecateIdpId: hecateIdp.id,
    permissions,
  });

  for (const missing of plan.missingGroups)
    console.warn(`claim group "${missing}" has no NetBird group; skipped`);

  if (plan.updates.length === 0) console.log("no changes");
  for (const upd of plan.updates) {
    const tag = upd.userId.slice(0, 8);
    console.log(
      `${tag}: ${upd.added.map((n) => `+${n}`).join(" ") || "(no adds)"} ` +
        `${upd.removed.map((n) => `-${n}`).join(" ") || "(no removals)"}`,
    );
  }

  if (env.dryRun) {
    console.log(`DRY_RUN: ${plan.updates.length} update(s) not applied`);
    return;
  }

  const byId = new Map(users.map((u) => [u.id, u]));
  for (const upd of plan.updates) {
    const user = byId.get(upd.userId)!;
    const res = await fetch(`${env.netbirdApi}/users/${upd.userId}`, {
      method: "PUT",
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
      throw new Error(`PUT user ${upd.userId.slice(0, 8)}: HTTP ${res.status}`);
  }
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
