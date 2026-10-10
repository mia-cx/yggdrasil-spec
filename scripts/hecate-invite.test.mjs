import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:http";
import { promisify } from "node:util";
import { test } from "node:test";

const exec = promisify(execFile);
const script = new URL("./hecate-invite.mjs", import.meta.url).pathname;

async function runInvite(t, { existingUser = false, emailStatus = 204 } = {}) {
  const requests = [];
  const server = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    requests.push({
      path: request.url,
      method: request.method,
      body: body ? JSON.parse(body) : undefined,
    });
    assert.equal(request.headers.authorization, "Bearer local-test-token");
    response.setHeader("Content-Type", "application/json");
    if (request.url.startsWith("/api/v3/flows/instances/")) {
      response.end(
        JSON.stringify({
          pagination: { count: 1 },
          results: [{ pk: "flow-id" }],
        }),
      );
    } else if (request.url.startsWith("/api/v3/core/users/")) {
      response.end(
        JSON.stringify({
          pagination: { count: Number(existingUser) },
          results: [],
        }),
      );
    } else if (request.url.endsWith("/send_email/")) {
      response.writeHead(emailStatus).end();
    } else {
      response.writeHead(201).end(JSON.stringify({ pk: "invitation-id" }));
    }
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => {
    server.closeAllConnections();
    return new Promise((resolve) => server.close(resolve));
  });
  const env = {
    ...process.env,
    AUTHENTIK_TOKEN: "local-test-token",
    AUTHENTIK_URL: `http://127.0.0.1:${server.address().port}`,
  };
  const result = await exec(
    process.execPath,
    [script, "person+invite@example.com"],
    { env },
  ).catch((error) => error);
  return { result, requests };
}

test("creates one email-bound invitation and queues its email to that recipient", async (t) => {
  const { result, requests } = await runInvite(t);
  assert.match(result.stdout, /email queued/);
  assert.equal(requests.length, 4);
  assert.equal(
    requests[1].path,
    "/api/v3/core/users/?email=person%2Binvite%40example.com",
  );
  const invitation = requests[2].body;
  assert.equal(invitation.flow, "flow-id");
  assert.equal(invitation.single_use, true);
  assert.deepEqual(invitation.fixed_data, {
    email: "person+invite@example.com",
  });
  const remaining = Date.parse(invitation.expires) - Date.now();
  assert.ok(
    remaining > 47 * 60 * 60 * 1000 && remaining <= 48 * 60 * 60 * 1000,
  );
  assert.equal(
    requests[3].path,
    "/api/v3/stages/invitation/invitations/invitation-id/send_email/",
  );
  assert.deepEqual(requests[3].body, {
    email_addresses: ["person+invite@example.com"],
    template: "email/invitation.html",
  });
});

test("refuses an existing account before creating or emailing an invitation", async (t) => {
  const { result, requests } = await runInvite(t, { existingUser: true });
  assert.equal(result.code, 1);
  assert.match(result.stderr, /account already uses this email/);
  assert.ok(requests.every((request) => request.method === "GET"));
});

test("reports a recoverable queue failure without retrying or deleting the invitation", async (t) => {
  const { result, requests } = await runInvite(t, { emailStatus: 503 });
  assert.equal(result.code, 1);
  assert.match(result.stderr, /Invitation created, but email queuing failed/);
  assert.equal(requests.length, 4);
  assert.equal(result.stdout, "");
  assert.doesNotMatch(result.stderr, /local-test-token|invitation-id/);
});
