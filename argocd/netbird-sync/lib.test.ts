import assert from "node:assert/strict";
import { describe, it } from "node:test";
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

// Encode a Dex-shaped user id: protobuf field 1 = sub, field 2 = connector
// id. Test subs stay under 128 bytes, so a single-byte length is exact.
const dexId = (sub: string, connector: string): string => {
  const field = (n: number, s: string) =>
    Buffer.concat([
      Buffer.from([(n << 3) | 2, s.length]),
      Buffer.from(s, "utf8"),
    ]);
  return Buffer.concat([field(1, sub), field(2, connector)]).toString("base64");
};

const groups: NbGroup[] = [
  { id: "g-sonarr", name: "svc-sonarr", issued: "jwt" },
  { id: "g-jellyfin", name: "svc-jellyfin", issued: "jwt" },
  { id: "g-enroll", name: "netbird-enroll", issued: "jwt" },
  { id: "g-api", name: "api-made", issued: "api" },
  { id: "g-seerr", name: "svc-seerr", issued: "jwt" },
  { id: "g-canary", name: "svc-canary", issued: "jwt" },
  { id: "g-proxmox", name: "svc-proxmox", issued: "jwt" },
  { id: "g-ssh", name: "svc-ssh", issued: "jwt" },
  { id: "g-dns", name: "dns-adguard", issued: "api" },
];

const hecateUser = (sub: string, autoGroups: string[]): NbUser => ({
  id: dexId(sub, "authentik"),
  role: "user",
  is_blocked: false,
  idp_id: "idp-hecate",
  auto_groups: autoGroups,
});

const plan = (users: NbUser[], permissions: Map<string, readonly string[]>) =>
  planUserUpdates({ users, groups, hecateIdpId: "idp-hecate", permissions });

describe("decodeDexUserId", () => {
  it("decodes a standard base64 protobuf id", () => {
    assert.deepEqual(decodeDexUserId(dexId("abc123", "authentik")), {
      sub: "abc123",
      connectorId: "authentik",
    });
  });

  it("accepts url-safe and unpadded variants", () => {
    const std = dexId("user-?+/", "conn"); // bytes that yield + and / in base64
    assert.ok(std.includes("+") || std.includes("/") || std.includes("="));
    const urlSafe = std.replace(/\+/g, "-").replace(/\//g, "_");
    const unpadded = urlSafe.replace(/=+$/, "");
    assert.equal(decodeDexUserId(urlSafe).sub, "user-?+/");
    assert.equal(decodeDexUserId(unpadded).sub, "user-?+/");
  });

  it("throws on malformed input", () => {
    assert.throws(() => decodeDexUserId("!!!"));
    assert.throws(() =>
      decodeDexUserId(Buffer.from("plain text").toString("base64")),
    );
    assert.throws(() => decodeDexUserId(dexId("only-sub", "").slice(0, 8)));
  });
});

describe("planUserUpdates", () => {
  it("adds a granted permission", () => {
    const u = hecateUser("u1", ["g-enroll"]);
    const { updates, missingGroups } = plan(
      [u],
      new Map([["u1", ["netbird-enroll", "svc-sonarr"]]]),
    );
    assert.equal(missingGroups.length, 0);
    assert.equal(updates.length, 1);
    assert.deepEqual(updates[0]!.added, ["svc-sonarr"]);
    assert.deepEqual(updates[0]!.removed, []);
    assert.deepEqual(updates[0]!.autoGroups, ["g-enroll", "g-sonarr"]);
  });

  it("removes a revoked permission", () => {
    const u = hecateUser("u1", ["g-enroll", "g-sonarr"]);
    const { updates } = plan([u], new Map([["u1", ["netbird-enroll"]]]));
    assert.deepEqual(updates[0]!.removed, ["svc-sonarr"]);
    assert.deepEqual(updates[0]!.autoGroups, ["g-enroll"]);
  });

  it("keeps api-issued groups on the user", () => {
    const u = hecateUser("u1", ["g-api", "g-sonarr"]);
    const { updates } = plan([u], new Map([["u1", ["svc-jellyfin"]]]));
    assert.deepEqual(updates[0]!.autoGroups.sort(), ["g-api", "g-jellyfin"]);
  });

  it("drops every managed group for a deleted/inactive Hecate user but keeps api groups", () => {
    const u = hecateUser("gone", ["g-api", "g-sonarr", "g-enroll"]);
    const { updates } = plan([u], new Map()); // no Authentik user -> no permissions
    assert.deepEqual(updates[0]!.autoGroups, ["g-api"]);
    assert.deepEqual(updates[0]!.removed.sort(), [
      "netbird-enroll",
      "svc-sonarr",
    ]);
  });

  it("throws when a Hecate-idp user has a malformed id", () => {
    const bad: NbUser = {
      id: "not-a-dex-id",
      role: "user",
      idp_id: "idp-hecate",
      auto_groups: [],
    };
    assert.throws(() => plan([bad], new Map()), /undecodable Hecate id/);
  });

  it("never touches non-Hecate users", () => {
    const local: NbUser = {
      id: "x",
      role: "owner",
      idp_id: "local",
      auto_groups: ["g-sonarr"],
    };
    const service: NbUser = { id: "y", role: "admin", auto_groups: [] };
    const { updates } = plan([local, service], new Map());
    assert.equal(updates.length, 0);
  });

  it("emits nothing for an unchanged user", () => {
    const u = hecateUser("u1", ["g-sonarr", "g-enroll"]);
    const { updates } = plan(
      [u],
      new Map([["u1", ["svc-sonarr", "netbird-enroll"]]]),
    );
    assert.equal(updates.length, 0);
  });

  it("reports claim groups with no NetBird group instead of creating them", () => {
    const u = hecateUser("u1", []);
    const { updates, missingGroups } = plan(
      [u],
      new Map([["u1", ["svc-nonexistent", "svc-sonarr"]]]),
    );
    assert.deepEqual(missingGroups, ["svc-nonexistent"]);
    assert.deepEqual(updates[0]!.autoGroups, ["g-sonarr"]);
  });
});

describe("alertTransition", () => {
  const cases = [
    [false, true, "failing"],
    [true, false, "recovered"],
    [false, false, null],
    [true, true, null],
  ] as const;
  for (const [was, now, expected] of cases) {
    it(`was ${was}, now ${now} -> ${expected}`, () => {
      assert.equal(alertTransition(was, now), expected);
    });
  }
});

// --- TV / peer planning -------------------------------------------------------

const peer = (
  id: string,
  name: string,
  groupIds: string[],
  userId?: string,
): NbPeer => ({
  id,
  name,
  user_id: userId,
  groups: groupIds.map((gid) => ({
    id: gid,
    name: groups.find((g) => g.id === gid)!.name,
  })),
});

const tvLink = (
  tv: string,
  peerId: string,
  ownerGroups: readonly string[],
  allowlist: readonly string[],
): TvLink => ({ tv, peerId, ownerGroups, allowlist });

const planPeers = (peers: NbPeer[], tvLinks: TvLink[]) =>
  planPeerUpdates({ peers, groups, tvLinks });

describe("planPeerUpdates", () => {
  it("grants a TV only the owner-groups intersected with its allowlist", () => {
    const p = peer("p1", "tv-living", []);
    const { changes, groupEdits, problems } = planPeers(
      [p],
      [
        tvLink(
          "tv-living",
          "p1",
          ["svc-jellyfin", "svc-seerr", "svc-ssh", "svc-proxmox"],
          ["svc-jellyfin", "svc-canary"],
        ),
      ],
    );
    assert.equal(problems.length, 0);
    assert.equal(changes.length, 1);
    assert.deepEqual(changes[0]!.added, ["svc-jellyfin"]);
    assert.deepEqual(groupEdits, [
      { groupId: "g-jellyfin", add: ["p1"], remove: [] },
    ]);
  });

  it("strips a TV when the owner loses the permission", () => {
    const p = peer("p1", "tv-living", ["g-jellyfin"]);
    const { changes, groupEdits } = planPeers(
      [p],
      [tvLink("tv-living", "p1", [], ["svc-jellyfin"])],
    );
    assert.deepEqual(changes[0]!.removed, ["svc-jellyfin"]);
    assert.deepEqual(groupEdits, [
      { groupId: "g-jellyfin", add: [], remove: ["p1"] },
    ]);
  });

  it("strips jwt groups from unlinked peers but keeps api groups", () => {
    const stale = peer("p1", "stale-setup-key-peer", ["g-jellyfin", "g-dns"]);
    const router = peer("p2", "olympus-router-1", ["g-dns"]);
    const { changes, groupEdits } = planPeers([stale, router], []);
    assert.equal(changes.length, 1);
    assert.deepEqual(changes[0]!.removed, ["svc-jellyfin"]);
    assert.equal(changes[0]!.tv, undefined);
    assert.deepEqual(groupEdits, [
      { groupId: "g-jellyfin", add: [], remove: ["p1"] },
    ]);
  });

  it("refuses to touch a user-owned peer and reports the problem", () => {
    const p = peer("p1", "mia-laptop", ["g-sonarr"], "some-user-id");
    const { changes, problems } = planPeers(
      [p],
      [tvLink("tv-x", "p1", ["svc-jellyfin"], ["svc-jellyfin"])],
    );
    assert.equal(changes.length, 0);
    assert.equal(problems.length, 1);
    assert.match(problems[0]!, /belongs to a user/);
  });

  it("fails closed when two links claim one peer", () => {
    const p = peer("p1", "tv-shared", ["g-jellyfin"]);
    const { changes, problems } = planPeers(
      [p],
      [
        tvLink("tv-a", "p1", ["svc-jellyfin"], ["svc-jellyfin"]),
        tvLink("tv-b", "p1", ["svc-jellyfin"], ["svc-jellyfin"]),
      ],
    );
    assert.equal(problems.length, 1);
    assert.equal(changes.length, 1);
    assert.deepEqual(changes[0]!.removed, ["svc-jellyfin"]);
    assert.deepEqual(changes[0]!.added, []);
  });

  it("aggregates edits per group and reports unknown peers", () => {
    const p1 = peer("p1", "tv-a-peer", []);
    const p2 = peer("p2", "tv-b-peer", []);
    const correct = peer("p3", "tv-c-peer", ["g-jellyfin"]);
    const { changes, groupEdits, unknownPeers } = planPeers(
      [p1, p2, correct],
      [
        tvLink("tv-a", "p1", ["svc-jellyfin"], ["svc-jellyfin"]),
        tvLink("tv-b", "p2", ["svc-jellyfin"], ["svc-jellyfin"]),
        tvLink("tv-c", "p3", ["svc-jellyfin"], ["svc-jellyfin"]),
        tvLink("tv-ghost", "p-missing", ["svc-jellyfin"], ["svc-jellyfin"]),
      ],
    );
    assert.equal(changes.length, 2); // tv-c already correct: no change
    assert.deepEqual(groupEdits, [
      { groupId: "g-jellyfin", add: ["p1", "p2"], remove: [] },
    ]);
    assert.deepEqual(unknownPeers, ["tv-ghost"]);
  });
});
