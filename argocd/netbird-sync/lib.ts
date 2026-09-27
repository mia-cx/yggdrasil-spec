// Pure logic for the hourly Hecate -> NetBird permission sync.
// No IO here; main.ts feeds this NetBird state and the permission map built
// from Authentik scope-mapping tests.

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

export const alertTransition = (
  wasFailing: boolean,
  failing: boolean,
): "failing" | "recovered" | null => {
  if (!wasFailing && failing) return "failing";
  if (wasFailing && !failing) return "recovered";
  return null;
};
