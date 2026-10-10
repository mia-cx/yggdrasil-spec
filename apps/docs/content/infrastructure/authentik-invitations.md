---
title: Hecate invitations
---

# Hecate invitations

Prepared for Authentik **2026.8.1**, the version pinned in this repository.
The blueprint requires review and explicit approval before importing into live
Hecate. It lives outside ArgoCD's watched paths.

## Account creation

1. Mia enters one email address. Authentik sends a single-use invitation valid for 48 hours.
2. The recipient opens the link and enters their name, username, password, and password confirmation.
3. They choose **Passkey** or **Authenticator app** and complete setup.
4. Hecate activates their account and signs them in.

The invitation supplies the email address. The recipient cannot replace it.
There is no second verification email. The password requires at least 12 characters.
Passkeys require user verification and discoverable credentials; device and password-manager passkeys are allowed.

## Prepare Hecate

Import `config/authentik/invitation-enrollment.yaml`
through **Customization > Blueprints** after approval.
It creates the `hecate-invitation-enrollment` flow and its own stages and policies.
It does not replace a brand's authentication or enrollment flow, change existing
SSO integrations, or grant service permissions.

Before rollout, inspect the current authentication flow. Require TOTP or WebAuthn
in its MFA validation stage before User Login. Set **Not configured action** to
**Configure** with the passkey and TOTP configuration stages. Review this change
separately because it can require existing users to enroll MFA too. Enrollment
alone does not make MFA mandatory on later sign-ins.

Keep every other enrollment route invitation-only or disabled, including source
enrollment flows. Adding this flow alone does not disable other registration paths.

## Invite someone

Once rollout is approved, set `AUTHENTIK_TOKEN` in your shell from an API token.
It needs permission to read flows and users, create invitations, and send their emails.

```bash
node scripts/hecate-invite.mjs person@example.com
```

The helper binds the email to the invitation and queues the native Authentik email
through the existing SMTP configuration. It uses `https://id.mia.cx`; an
`AUTHENTIK_URL` override supports another HTTPS instance or an isolated loopback test.
It refuses an email that already belongs to an account.

Authentik queues email asynchronously. A successful command means **queued**, not
delivered. Check System Tasks and the recipient's inbox during the approved pilot.
Verify the email link uses `https://id.mia.cx`, including correct forwarded scheme
headers on the ingress.

For the native admin UI, create an invitation under **Directory > Invitations**.
Select `hecate-invitation-enrollment`, enable **Single use**, set a 48-hour expiry,
and enter these custom attributes:

```yaml
email: person@example.com
```

Use **Send via Email** with that same recipient and the default Invitation template.
Create one invitation per person. A shared single-use link is not a batch invitation.

## Interrupted setup

The flow checks the link before showing the account form. The native Invitation
stage runs after form submission, so opening the link does not consume it.
Missing, malformed, expired, deleted, and wrong-flow invitations cannot enroll.

Authentik 2026.8.1 consumes a single-use invitation when its Invitation stage runs,
rather than when the entire enrollment completes. After account submission, the
recipient should finish MFA in the same browser session. An interrupted session
can leave an inactive account under `users/invited`; it cannot sign in.
To restart after losing the session, Mia checks and deletes only that unfinished
inactive account, then sends a fresh invitation. Do not activate it manually to
bypass MFA.

Service permissions and role presets remain separate Hecate assignments.
People and invitation tokens never belong in this repository.

## Pilot checks

- Complete onboarding once with TOTP and once with a passkey, including a later sign-in requiring the selected method.
- Open a fresh invitation twice without submitting. Confirm both visits show the form and the invitation still exists.
- Reject missing, malformed, expired, revoked, reused, and wrong-flow links. Submit a forged email and confirm the invitation's email wins.
- Abandon MFA and confirm the inactive account cannot sign in. Exercise the restart procedure.
- Verify actual delivery and the public HTTPS link, plus existing SSO and invitation-only registration, before rollout.

References: [Invitations](https://docs.goauthentik.io/users-sources/user/invitations/),
[Authenticator validation](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_validate/),
[WebAuthn setup](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_webauthn/),
and [the 2026.8.1 invitation implementation](https://github.com/goauthentik/authentik/blob/version/2026.8.1/authentik/stages/invitation/stage.py).
