import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  alertTransition,
  decodeDexUserId,
  planUserUpdates,
  type NbGroup,
  type NbUser,
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
