#!/usr/bin/env node
import { randomUUID } from "node:crypto";

// Create one email-bound invitation and let Authentik's worker send its email.
// Run only after the invitation flow has been imported and rollout approved.
const flowSlug = "hecate-invitation-enrollment";
const invitationLifetimeMs = 48 * 60 * 60 * 1000;

async function main() {
  const [email, ...extra] = process.argv.slice(2);
  if (!email || extra.length || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new Error("Usage: node scripts/hecate-invite.mjs person@example.com");
  }
  const token = process.env.AUTHENTIK_TOKEN;
  if (!token) throw new Error("Set AUTHENTIK_TOKEN to an Authentik API token.");
  const origin = new URL(process.env.AUTHENTIK_URL || "https://id.mia.cx");
  if (
    origin.username ||
    origin.password ||
    origin.pathname !== "/" ||
    origin.search ||
    origin.hash ||
    (origin.protocol !== "https:" &&
      !(origin.protocol === "http:" && origin.hostname === "127.0.0.1"))
  ) {
    throw new Error(
      "AUTHENTIK_URL must be an HTTPS origin, or HTTP on 127.0.0.1 for local testing.",
    );
  }

  async function api(path, body) {
    const response = await fetch(new URL(`/api/v3/${path}`, origin), {
      method: body ? "POST" : "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
      redirect: "error",
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok)
      throw new Error(`Authentik request failed (${response.status}).`);
    return response.status === 204 ? undefined : response.json();
  }

  const flows = await api(`flows/instances/?slug=${flowSlug}`);
  if (flows.pagination.count !== 1) {
    throw new Error("Import the Hecate invitation enrollment blueprint first.");
  }
  const users = await api(`core/users/?email=${encodeURIComponent(email)}`);
  if (users.pagination.count) {
    throw new Error(
      "An account already uses this email. Use account recovery instead.",
    );
  }
  const invitation = await api("stages/invitation/invitations/", {
    name: `invite-${randomUUID()}`,
    flow: flows.results[0].pk,
    single_use: true,
    expires: new Date(Date.now() + invitationLifetimeMs).toISOString(),
    fixed_data: { email },
  });
  try {
    await api(`stages/invitation/invitations/${invitation.pk}/send_email/`, {
      email_addresses: [email],
      template: "email/invitation.html",
    });
  } catch (error) {
    throw new Error(
      "Invitation created, but email queuing failed. Retry from Directory > Invitations in Authentik.",
      { cause: error },
    );
  }
  console.log(`Invitation email queued for ${email}. Expires in 48 hours.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
