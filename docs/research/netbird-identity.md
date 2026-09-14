# Hecate permissions and native clients

Research dated 2026-09-14 for [Service permissions with Authentik and native clients](https://github.com/mia-cx/yggdrasil-spec/issues/7), within [Private Yggdrasil access with NetBird and Hecate](https://github.com/mia-cx/yggdrasil-spec/issues/5). Scope follows the proposal in [Choose service permissions and public boundaries](https://github.com/mia-cx/yggdrasil-spec/issues/8). This is a design recommendation, not deployed configuration. No live secrets, installations, or device tests were accessed.

Use Hecate application bindings for service entry, group hierarchy for role presets, and native application authentication where supported. Jellyfin 12 SSO remains a migration gate. Network membership alone cannot enforce different applications sharing one ingress IP and port.

## Permissions and role presets

Authentik's **Roles** grant administrative permissions over Authentik objects. They are not the proposed Media viewer or Personal apps user presets. Application policy/group/user bindings control service entry. An application without applicable bindings permits access by default. Every protected application therefore needs an explicit binding. [Roles](https://docs.goauthentik.io/users-sources/roles/), [binding evaluation](https://docs.goauthentik.io/customize/policies/bindings/).

Recommended implementation on Authentik 2026.8.1:

1. Create one group per permission, using the proposed names such as `jellyfin.access` and `seerr.access`.
2. Represent each preset as a group, such as `preset.media-requester`. Its **parents** are `jellyfin.access` and `seerr.access`. Members inherit both permissions. Give users several preset memberships as needed. Direct service-group membership can implement one-off grants if Mia accepts them.
3. Bind each application's entry policy to its service group. Keep application administrator privileges separate. Infrastructure operator must not inherit personal-content groups.
4. Keep `netbird.enroll` separate from `netbird.admin`. Assign actual NetBird administrative roles explicitly. Implement `authentik.admin` through narrowly chosen Authentik administrative permissions, not an application-launcher shortcut.

This hierarchy is supported by the exact installed-version source. `Group.parents` is many-to-many; `User.all_groups()` expands ancestors. `all_roles()` also inherits administrative roles through those ancestors. Keep superuser groups outside ordinary presets. [Authentik 2026.8.1 models](https://github.com/goauthentik/authentik/blob/version/2026.8.1/authentik/core/models.py#L172).

**Claims need an explicit mapping.** The shipped `profile` scope uses `request.user.groups.all()`, which includes direct groups only. An inherited permission can pass an application binding while disappearing from its default OAuth claims. Create a NetBird-specific scope mapping, request that scope, and include its claims in the token consumed by NetBird:

```python
return {"netbird_groups": [
    group.name for group in request.user.all_groups()
    if group.name == "netbird.enroll" or group.name.endswith(".access")
]}
```

Configure NetBird's JWT group claim as `netbird_groups` and its allowed enrollment group as `netbird.enroll`. This avoids competing mappings for `groups` and excludes Authentik administrative groups. Inspect an actual test token before accepting the configuration. [Versioned default mappings](https://github.com/goauthentik/authentik/blob/version/2026.8.1/blueprints/system/providers-oauth2.yaml#L30), [NetBird claim configuration](https://docs.netbird.io/selfhosted/identity-providers/generic-oidc).

If the embedded identity provider forwards only standard `groups`, replace the NetBird provider's default profile mapping with a custom copy. Preserve its profile fields and replace its group expression with the filtered effective-membership expression above. Use `groups` throughout that integration. Verify the final NetBird token, not only Hecate's upstream token.

Application entitlements are available since 2024.12. They express permissions *inside* a particular application, exposed through a scope mapping. They do not automatically enforce service entry. Use them only where an application consumes those claims. In 2026.8.1, `app_entitlements()` selects enabled user/group bindings using effective groups; it does not evaluate arbitrary policy bindings. The default scope emits both `entitlements` and `roles`. Neither means Authentik administrative Roles. [Entitlement documentation](https://docs.goauthentik.io/add-secure-apps/applications/manage_apps#application-entitlements), [versioned implementation](https://github.com/goauthentik/authentik/blob/version/2026.8.1/authentik/core/models.py#L484).

## NetBird propagation and removal

Current NetBird documentation supports Authentik through an external OIDC provider attached to the embedded identity provider. Prefer this documented route for a new self-hosted deployment; confirm the selected NetBird release supports it. The older standalone configuration is a distinct integration, including an Authentik management account. Do not mix its settings into embedded-provider instructions. [Current integration](https://docs.netbird.io/selfhosted/identity-providers/authentik), [standalone integration](https://docs.netbird.io/selfhosted/identity-providers/advanced/authentik).

JWT synchronization updates membership at login, not continuously after an Authentik edit. Enable and verify user-group propagation to already enrolled peers. A manually created NetBird group with the same name prevents JWT import; let JWT synchronization create imported groups before attaching policies. SCIM provisioning requires NetBird Cloud or a commercial self-hosted license. It is not a Community Edition baseline. [Synchronization limits](https://docs.netbird.io/selfhosted/identity-providers), [propagation setting](https://docs.netbird.io/api/resources/accounts).

Peer login expiration applies to interactive SSO devices. Setup-key peers are exempt; individual SSO peers can also disable expiration. Treat TV enrollment identity as a person/device association, not a reusable setup key granting permanent viewer access. [Peer expiration](https://docs.netbird.io/manage/settings/enforce-periodic-user-authentication).

Recommended removal procedure must address each enforcement layer: remove the Hecate grant, invalidate relevant identity sessions/tokens, remove or block affected NetBird access, and revoke application sessions/device tokens. For one service, revoke that service without disabling unrelated grants. JWT refresh, application cookies, proxy sessions, playback tokens, and offline peers can delay enforcement. No cited integration establishes an immediate universal revocation bound. Choose the acceptable delay with Mia and measure it before migration.

## Service compatibility

“Proxy candidate” means browser entry protection, subject to validation. It does not claim native SSO, individual application accounts, or safe blanket protection of machine endpoints. Source/main and rolling documentation establish a candidate capability only; exact installed versions still need confirmation where noted.

Use a separate Authentik application/provider for each browser service and its aliases. Strip client-supplied identity headers and prevent direct-origin bypass. Native/local login exceptions need an explicit account grant/removal process tied to the service permission. An existing Jellyfin password must not bypass a removed `jellyfin.access` grant. Until account enforcement or a distinct service network destination is proven, that service has not met the permission requirement.

| Service | Hecate integration and native-access treatment |
| --- | --- |
| Jellyfin 12 | Plugin-based OIDC is a testing candidate; preserve native authentication/device tokens and playback without forward-auth. See gate below. |
| Seerr | Official settings document local and Jellyfin/Emby/Plex sign-in, not generic Hecate OIDC. Proxy candidate for UI, retaining Seerr users and request permissions. Gate `seerr.access` independently from Jellyfin; media-server access can otherwise admit new users. [Settings](https://docs.seerr.dev/using-seerr/settings/users/). |
| Sonarr | Proxy candidate for UI; native OIDC unverified. Keep workload API authentication on a separate internal route. [Authentication guidance](https://wiki.servarr.com/sonarr/faq). |
| Radarr | Same browser/API separation; independent `radarr.access`. Installed authentication mode needs verification. |
| Lidarr | Same separation; independent `lidarr.access`. Native OIDC unverified. |
| Readarr | Same separation; independent `readarr.access`. Native OIDC unverified. |
| Prowlarr | Same separation; independent `prowlarr.access`. Preserve indexer/API traffic between workloads. |
| SABnzbd | Proxy candidate for UI; native OIDC unverified. Preserve downloader API credentials and workload route. [Configuration](https://sabnzbd.org/wiki/configuration/4.5/special). |
| qBittorrent | Proxy candidate for UI; documented API uses its own login and SID cookie. Keep downloader API access and BitTorrent TCP/UDP traffic separate. [API](https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0)). |
| Tdarr | Proxy candidate for UI; exact build's SSO support unverified. Server/node transport remains a workload exception, not a browser permission. |
| Tunarr | Proxy candidate for management; exact build's SSO support unverified. Jellyfin playback, guide and tuner endpoints require separate machine/client paths. |
| Immich 3.1 | Native OIDC candidate. Documented mobile callback is `app.immich:///oauth-callback`; test matching server/mobile versions. Current docs describe optional backchannel logout and creation-only role/quota claims; verify those details against 3.1 before using them. No browser gate around uploads/API. [OAuth](https://docs.immich.app/administration/oauth/). |
| Nextcloud 34 | First-party `user_oidc` app provides OIDC; release 8.11.0 declares Nextcloud 29–35 compatibility. Check installed app/version. Preserve native sync/WebDAV authentication, app tokens, shares and federation. [App](https://github.com/nextcloud/user_oidc), [version bounds](https://github.com/nextcloud/user_oidc/blob/v8.11.0/appinfo/info.xml). |
| Vaultwarden 1.37.2 | Native OIDC exists in this exact release. SSO does not replace the vault master password. Preserve Bitwarden mobile/desktop/extension protocols. Test initial linking, unlock, refresh and revocation; `SSO_AUTH_ONLY_NOT_SESSION` changes session lifecycle. [Versioned configuration](https://github.com/dani-garcia/vaultwarden/blob/1.37.2/src/config.rs#L814), [SSO guide](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect). |
| Pelican / Wings | Upstream panel source includes an Authentik OAuth provider. Verify the deployed digest contains it. Keep application privileges explicit; Wings API, console WebSockets, SFTP and game traffic need native handling. [Provider source](https://github.com/pelican-dev/panel/blob/main/app/Extensions/OAuth/Schemas/AuthentikSchema.php). |
| Hermes | Repository documents existing dashboard OIDC and `/auth/callback`. Preserve it; deployed implementation and revocation still need verification. Graph webhook and MCP OAuth callbacks are separate routes. [Dashboard](../../apps/docs/content/services/hermes-dashboard.md), [routes](../../argocd/hermes-dashboard/ingressroute.yaml). |
| Microsoft 365 MCP | Existing `/authorize` uses forward-auth. `/mcp`, metadata and `/token` use private machine access. Microsoft consent authenticates Microsoft access; Hecate gates entry separately. [Current contract](../../argocd/ms365-mcp/README.md). |
| Email OAuth2 proxy | Existing browser ingress uses Authentik. SMTP uses application credentials with Microsoft client-credentials OAuth; this deployment requires no interactive callback. [Configuration](../../argocd/email-oauth2-proxy/README.md), [ingress](../../argocd/email-oauth2-proxy/ingressroute.yaml). |
| ArgoCD 3.3 | Native OIDC supports an existing provider. Keep ArgoCD RBAC and CLI SSO/API tokens; service entry does not grant cluster administration. [Versioned guide](https://argo-cd.readthedocs.io/en/release-3.3/operator-manual/user-management/). |
| Longhorn | Proxy candidate for UI. Official ingress guidance supplies external authentication; do not apply the browser gate to storage/control traffic. Check installed version. [Ingress](https://longhorn.io/docs/archives/1.10.0/deploy/accessing-the-ui/longhorn-ingress/). |
| NetBird | OIDC enrollment as above; actual administrative role remains separate from imported access groups. Management/signal/relay/STUN must support enrollment before mesh access. |
| Authentik / Hecate | Existing identity login remains the bootstrap service. Administrative access uses Authentik RBAC. Normal login must not require `authentik.admin`. |
| Proxmox | Native OpenID Connect realm is documented; verify installed release. Preserve Proxmox ACLs, scoped API tokens, console protocols and local recovery access. [Maintained documentation source](https://github.com/proxmox/pve-docs/blob/master/pveum.adoc). |

OpenSpeedTest and retained Caelestis stay outside new permission enforcement. Workload-only services from the inventory retain machine policies, not human login grants.

## Jellyfin and rollout gates

The old [9p4 plugin repository](https://github.com/9p4/jellyfin-plugin-sso/releases) is archived and its documented release targets Jellyfin 10.11. [Flowfin's Jellyfin 12 beta](https://github.com/Flowfin/jellyfin-plugin-sso/releases/tag/5.0.0-JF12-beta.85) supplies a .NET 10 build, but explicitly reports no manual live Jellyfin 12 release-QA pass. Automated provider tests are not evidence for Mia's mobile or Apple TV clients. Do not reactivate the quarantined plugin or call the replacement production-ready.

[NetBird tvOS documentation](https://docs.netbird.io/get-started/install/tvos) supports tvOS 17+, a custom management URL, and QR SSO when self-hosted Device Authentication is enabled. This connects the TV to the mesh; Jellyfin still needs its own supported login. Test native credentials or Quick Connect where the chosen player supports it. Preserve those methods until plugin/client compatibility is demonstrated.

Acceptance gates for a later authorized test:

1. Prove direct and inherited grants agree across application binding, emitted token and every enrolled peer. Removing one preset must preserve other grants. Confirm entry grants never confer application administration.
2. Test home LAN and remote access, including direct backend addresses. A connected unauthorized user may see login/denial, but cannot fetch content or operate APIs. Same-IP/port application separation must come from application enforcement or separate destinations.
3. Test Jellyfin mobile and exact Apple TV player builds: enrollment, login/pairing, direct play, transcoding, seek, reconnect and permission removal during playback. A shared TV's mesh owner and Jellyfin viewer may differ; document which identity governs each layer.
4. Test sensitive apps' mobile/sync clients, API integrations, account linking and removal using existing sessions. Record revocation delay, including during identity/management outages. No deployment passes on browser login alone.
5. From off-mesh, confirm private hostnames show connection instructions and Hecate/NetBird enrollment still works. Connect before starting private-app OAuth. Browser callbacks may remain private; identity discovery/token/JWKS and backchannel logout need server reachability. Externally delivered Graph webhooks require separate public delivery. Preserve Hermes callbacks, outpost routes, public shares and federation according to the exposure decision.
