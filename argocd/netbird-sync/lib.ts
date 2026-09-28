// Pure logic for the hourly Hecate -> NetBird permission sync.
// No IO here; main.ts feeds this NetBird state and the permission map built
// from Authentik scope-mapping tests. Two planners: users (jwt auto_groups)
// and peers (TV links grant jwt groups to setup-key peers).

export interface NbUser {
  id: string;
  role: string;
  auto_groups?: string[];
  is_blocked?: boolean;
  idp_id?: string;
}

export interface NbGroup {
  id: string;
  name: string;
  issued?: string;
}

export interface PlanInput {
  users: NbUser[];
  groups: NbGroup[];
  hecateIdpId: string;
  /** Hecate sub -> claim group names, for active Authentik users only. */
  permissions: ReadonlyMap<string, readonly string[]>;
}

export interface UserUpdate {
  userId: string;
  autoGroups: string[];
  added: string[];
  removed: string[];
}

export interface Plan {
  updates: UserUpdate[];
  missingGroups: string[];
}

const readVarint = (
  buf: Buffer,
  pos: number,
): [value: number, next: number] => {
  let result = 0;
  let shift = 0;
  for (;;) {
    if (pos >= buf.length) throw new Error("truncated varint");
    const byte = buf[pos++]!;
    result |= (byte & 0x7f) << shift;
    if (!(byte & 0x80)) return [result >>> 0, pos];
    shift += 7;
    if (shift > 28) throw new Error("varint too long");
  }
};

/**
 * NetBird stores Hecate user ids as Dex's base64-encoded protobuf:
 * field 1 (string) = Authentik `sub`, field 2 (string) = connector id.
 */
export const decodeDexUserId = (
  id: string,
): { sub: string; connectorId: string } => {
  const normalized = id.replace(/-/g, "+").replace(/_/g, "/");
  const buf = Buffer.from(normalized, "base64");
  if (buf.length === 0) throw new Error("not base64");

  let sub: string | undefined;
  let connectorId: string | undefined;
  let pos = 0;
  while (pos < buf.length) {
    const [tag, afterTag] = readVarint(buf, pos);
    pos = afterTag;
    const field = tag >>> 3;
    const wire = tag & 7;
    if (wire !== 2) throw new Error(`unexpected wire type ${wire}`);
    const [len, afterLen] = readVarint(buf, pos);
    pos = afterLen;
    if (pos + len > buf.length) throw new Error("truncated string field");
    const value = buf.subarray(pos, pos + len).toString("utf8");
    pos += len;
    if (field === 1) sub = value;
    else if (field === 2) connectorId = value;
  }
  if (sub === undefined || connectorId === undefined)
    throw new Error("missing sub or connector field");
  return { sub, connectorId };
};

/**
 * Diff each Hecate user's managed (jwt-issued) NetBird groups against the
 * permissions claim. Non-managed groups are always kept; non-Hecate users are
 * never touched; claim names with no NetBird group are reported, not created.
 */
export const planUserUpdates = ({
  users,
  groups,
  hecateIdpId,
  permissions,
}: PlanInput): Plan => {
  const managedNameById = new Map<string, string>();
  const managedIdByName = new Map<string, string>();
  for (const g of groups) {
    if (g.issued !== "jwt") continue;
    managedNameById.set(g.id, g.name);
    managedIdByName.set(g.name, g.id);
  }

  const missing = new Set<string>();
  const updates: UserUpdate[] = [];

  for (const u of users) {
    if (u.idp_id !== hecateIdpId) continue;

    // A Hecate-idp user whose id doesn't decode means the id format changed
    // upstream — fail loudly rather than silently skipping revocations.
    let sub: string;
    try {
      sub = decodeDexUserId(u.id).sub;
    } catch (err) {
      throw new Error(
        `user ${u.id.slice(0, 8)}: undecodable Hecate id: ${err instanceof Error ? err.message : err}`,
      );
    }

    const desired = permissions.get(sub) ?? [];
    const desiredSet = new Set(desired);

    const keptApi = (u.auto_groups ?? []).filter(
      (id) => !managedNameById.has(id),
    );
    const wantedManaged: string[] = [];
    for (const name of desiredSet) {
      const id = managedIdByName.get(name);
      if (id === undefined) missing.add(name);
      else wantedManaged.push(id);
    }
    const next = [...keptApi, ...wantedManaged].sort();
    const current = [...(u.auto_groups ?? [])].sort();
    if (
      next.length === current.length &&
      next.every((id, i) => id === current[i])
    )
      continue;

    const currentManagedNames = new Set(
      (u.auto_groups ?? [])
        .filter((id) => managedNameById.has(id))
        .map((id) => managedNameById.get(id)!),
    );
    updates.push({
      userId: u.id,
      autoGroups: next,
      added: desired.filter(
        (n) => !currentManagedNames.has(n) && managedIdByName.has(n),
      ),
      removed: [...currentManagedNames].filter((n) => !desiredSet.has(n)),
    });
  }

  return { updates, missingGroups: [...missing].sort() };
};

// --- TV / peer planning ------------------------------------------------------

export interface NbPeer {
  id: string;
  name: string;
  user_id?: string;
  groups: { id: string; name: string }[];
}

export interface TvLink {
  /** TV service-account username, for logs. */
  tv: string;
  peerId: string;
  /** Owner's claim groups; [] if the owner is inactive/deleted/not found. */
  ownerGroups: readonly string[];
  /** TV's own claim groups; [] if the TV account is inactive. */
  allowlist: readonly string[];
}

export interface PeerChange {
  peerId: string;
  peerName: string;
  tv?: string;
  added: string[];
  removed: string[];
}

export interface GroupEdit {
  groupId: string;
  add: string[];
  remove: string[];
}

export interface PeerPlan {
  changes: PeerChange[];
  groupEdits: GroupEdit[];
  missingGroups: string[];
  problems: string[];
}

/**
 * Plan jwt-group membership for non-user peers. A setup-key peer holds jwt
 * groups only through a TV link (owner groups intersected with the TV's
 * allowlist); unlinked or stale peers are stripped of jwt groups. User-owned
 * peers are never touched. Nothing throws: config problems are collected and
 * main.ts throws after applying everything else.
 */
export const planPeerUpdates = ({
  peers,
  groups,
  tvLinks,
}: {
  peers: NbPeer[];
  groups: NbGroup[];
  tvLinks: TvLink[];
}): PeerPlan => {
  const managedNameById = new Map<string, string>();
  const managedIdByName = new Map<string, string>();
  for (const g of groups) {
    if (g.issued !== "jwt") continue;
    managedNameById.set(g.id, g.name);
    managedIdByName.set(g.name, g.id);
  }

  const problems: string[] = [];
  const missing = new Set<string>();

  const peerById = new Map(peers.map((p) => [p.id, p]));
  const linkByPeerId = new Map<string, TvLink>();
  const duplicatePeerIds = new Set<string>();
  for (const link of tvLinks) {
    if (linkByPeerId.has(link.peerId)) {
      duplicatePeerIds.add(link.peerId);
      problems.push(
        `peer id ${link.peerId.slice(0, 8)} claimed by two TVs (${linkByPeerId.get(link.peerId)!.tv}, ${link.tv}); fail closed`,
      );
      continue;
    }
    linkByPeerId.set(link.peerId, link);
    if (!peerById.has(link.peerId))
      problems.push(
        `tv ${link.tv}: peer id ${link.peerId.slice(0, 8)} not found in NetBird`,
      );
  }

  const changes: PeerChange[] = [];
  const addsByGroup = new Map<string, Set<string>>();
  const removesByGroup = new Map<string, Set<string>>();

  for (const peer of peers) {
    const link = linkByPeerId.get(peer.id);
    if (peer.user_id) {
      if (link)
        problems.push(
          `tv ${link.tv}: peer ${peer.name} belongs to a user; not linked`,
        );
      continue; // user-owned peers are never touched
    }

    const desiredNames = new Set<string>();
    if (link && !duplicatePeerIds.has(peer.id)) {
      const allow = new Set(link.allowlist);
      for (const name of link.ownerGroups) {
        if (!allow.has(name)) continue;
        if (!managedIdByName.has(name)) {
          missing.add(name);
          continue;
        }
        desiredNames.add(name);
      }
    }

    const currentJwtNames = peer.groups
      .map((g) => g.name)
      .filter((n) => managedIdByName.has(n));
    const currentSet = new Set(currentJwtNames);
    const added = [...desiredNames].filter((n) => !currentSet.has(n));
    const removed = [...currentSet].filter((n) => !desiredNames.has(n));
    if (added.length === 0 && removed.length === 0) continue;

    changes.push({
      peerId: peer.id,
      peerName: peer.name,
      tv: link?.tv,
      added: added.sort(),
      removed: removed.sort(),
    });
    const bump = (map: Map<string, Set<string>>, groupId: string) => {
      let s = map.get(groupId);
      if (!s) map.set(groupId, (s = new Set()));
      s.add(peer.id);
    };
    for (const n of added) bump(addsByGroup, managedIdByName.get(n)!);
    for (const n of removed) bump(removesByGroup, managedIdByName.get(n)!);
  }

  const groupEdits: GroupEdit[] = [
    ...new Set([...addsByGroup.keys(), ...removesByGroup.keys()]),
  ]
    .sort()
    .map((groupId) => ({
      groupId,
      add: [...(addsByGroup.get(groupId) ?? [])].sort(),
      remove: [...(removesByGroup.get(groupId) ?? [])].sort(),
    }));

  return {
    changes,
    groupEdits,
    missingGroups: [...missing].sort(),
    problems,
  };
};

export const alertTransition = (
  wasFailing: boolean,
  failing: boolean,
): "failing" | "recovered" | null => {
  if (!wasFailing && failing) return "failing";
  if (wasFailing && !failing) return "recovered";
  return null;
};
