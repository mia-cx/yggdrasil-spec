---
title: Hecate invitations
---

# Hecate invitations

Mia approved both invitation blueprints, and we imported them into live Hecate on 10 October 2026.
Hecate runs Authentik **2026.8.1**. The blueprints live outside ArgoCD's watched paths.
Live stage and policy checks pass. The public flow rejects links without an invitation.
Mia confirmed receipt of both a test email and an invitation on 10 October 2026.
Enrollment with real devices remains a pilot check.
Live checks confirm admin-only access to the form and dashboard tile.

## Account creation

1. Mia enters an email address and chooses service groups. Authentik sends a single-use invitation valid for 48 hours.
2. The recipient opens the link and enters their name, username, password, and password confirmation.
3. They choose **Passkey** or **Authenticator app** and complete setup.
4. Hecate assigns the invited groups, activates their account, and signs them in.

The invitation supplies the email address. The recipient cannot replace it.
There is no second verification email. The password requires at least 12 characters.
Passkeys require user verification and discoverable credentials; device and password-manager passkeys are allowed.

## Configuration

The imported `config/authentik/invitation-enrollment.yaml` creates the
`hecate-invitation-enrollment` flow and its own stages and policies.
The original import preserved existing flows and brand assignments.
The group extension uses existing Hecate groups and application bindings; it does not create access rules.
For a fresh instance, import the blueprint through **Customization > Blueprints** after review and approval.
Import `config/authentik/admin-invitations.yaml` after the enrollment blueprint to add the admin form and dashboard tile.

Before rollout, inspect the current authentication flow. Require TOTP or WebAuthn
in its MFA validation stage before User Login. Set **Not configured action** to
**Configure** with the passkey and TOTP configuration stages. Review this change
separately because it can require existing users to enroll MFA too. Enrollment
alone does not make MFA mandatory on later sign-ins.

Keep every other enrollment route invitation-only or disabled, including source
enrollment flows. Adding this flow alone does not disable other registration paths.

## Invite someone

1. Open **Invite someone** on your application dashboard, or [open the form directly](https://id.mia.cx/if/flow/hecate-admin-invite/).
2. Enter the email address and tick the service groups to grant.
3. Select **Continue** to queue the invitation email. The next screen confirms the recipient.

The form is limited to active Authentik superusers. Ordinary users cannot see its tile or submit the form.
All groups start unchecked. The choices are Nextcloud, Jellyfin, Immich, Vaultwarden, Pelican, Proxmox, Media Admin, and NetBird.
NetBird selects the existing `netbird-enroll` group; other choices use their displayed group names.
The form grants no permissions until the recipient completes MFA setup.
For example, choosing Nextcloud assigns the existing `Nextcloud` group, which controls the live Nextcloud application.
Selecting no groups creates an account without these service grants.

The form stores selected group UUIDs in the invitation. Recipients cannot replace them with submitted fields.
Deleting a selected group before enrollment rejects the invitation. Deleting it during MFA prevents account activation.
If email queuing fails, the form removes the unfinished invitation and permits retry.

To extend the form, add a checkbox to the admin blueprint with `field_key: "group:<existing group name>"`.
Add that prompt to `hecate-admin-invitation-form` and re-import the reviewed blueprint.
Only existing groups can be selected; the form never creates groups.

### Native invitation dialog

For the existing admin dialog:

1. Open **Directory > Invitations** and create an invitation.
2. Select **Hecate invitation enrollment**, enable **Single use**, and set a 48-hour expiry.
3. Set **Custom attributes** to the recipient's email:

```yaml
email: person@example.com
```

4. Save, then use **Send via Email** with that same recipient and the default Invitation template.

Create one invitation per person. A shared single-use link is not a batch invitation.

### Email-only command

Set `AUTHENTIK_TOKEN` in your shell from an API token.
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

Later service-permission changes and role presets remain ordinary Hecate group assignments.
People and invitation tokens never belong in this repository.

## Pilot checks

- Complete onboarding once with TOTP and once with a passkey, including a later sign-in requiring the selected method.
- Open a fresh invitation twice without submitting. Confirm both visits show the form and the invitation still exists.
- Reject missing, malformed, expired, revoked, reused, and wrong-flow links. Submit a forged email and confirm the invitation's email wins.
- Abandon MFA and confirm the inactive account cannot sign in. Exercise the restart procedure.
- Verify actual delivery and the public HTTPS link, plus existing SSO and invitation-only registration, before rollout.

## Isolated verification

Both blueprints pass Authentik 2026.8.1's native importer.
The admin form passes browser checks at desktop and phone widths, including dashboard entry, group selection, queuing, and return to Invitations.
`scripts/hecate-invitation-flow.test.py` checks admin authorization, group tampering, MFA gating, deleted groups, and email-queue failure.
It requires a disposable Authentik instance with `AUTHENTIK_SECRET_KEY=isolated-invitation-test-only` and both blueprints imported.
It mocks outbound email and rolls back its database fixtures:

```bash
docker exec -i <isolated-authentik-container> ak shell \
  -c 'import sys; exec(compile(sys.stdin.read(), "hecate-invitation-flow.test.py", "exec"))' \
  < scripts/hecate-invitation-flow.test.py
```

References: [Invitations](https://docs.goauthentik.io/users-sources/user/invitations/),
[Authenticator validation](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_validate/),
[WebAuthn setup](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_webauthn/),
[User write and dynamic groups](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/user_write/),
and [the 2026.8.1 invitation implementation](https://github.com/goauthentik/authentik/blob/version/2026.8.1/authentik/stages/invitation/stage.py).
