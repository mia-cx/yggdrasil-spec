# Direction

Yggdrasil manages Mia's homelab infrastructure and access.
Keep infrastructure reproducible and onboarding simple.

For network architecture, read the [Wayfinder map](https://github.com/mia-cx/yggdrasil-spec/issues/5) and its accepted resolutions.
For migration execution, read the [NetBird migration plan](apps/docs/content/roadmaps/infrastructure/netbird-migration.md).
Each service cutover requires Mia's approval after its readiness checks.

## Hecate onboarding

Mia chose email invitations with name, username, password, and a choice of TOTP or passkey enrollment.
The account stays inactive until the recipient completes MFA setup.
Mia chose a separate admin invitation form with service-group choices.
The invitation holds those choices; the account receives them after MFA setup.

Mia approved the original enrollment flow's live import on 10 October 2026.
The import preserved existing authentication flows and brand assignments.
Email delivery and enrollment with real devices still need a pilot.
Mandatory MFA on later sign-ins and other enrollment routes remain separate rollout decisions.
The admin form and group assignment pass isolated tests; their live import still needs approval.

For dashboard instructions, configuration, and pilot checks, read [Hecate invitations](apps/docs/content/infrastructure/authentik-invitations.md).
