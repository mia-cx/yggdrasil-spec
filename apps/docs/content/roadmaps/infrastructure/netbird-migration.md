---
title: NetBird migration
---

# NetBird migration

Staged first-site migration to the new NetBird mesh, resolving [Choose migration order and acceptance checks](https://github.com/mia-cx/yggdrasil-spec/issues/14). This is a plan, not a started effort; execution comes later. The [Wayfinder map](https://github.com/mia-cx/yggdrasil-spec/issues/5) holds the accepted architecture. [NetBird](../../infrastructure/netbird.md) covers [per-service destinations](../../infrastructure/netbird.md#per-service-network-destinations), [permission revocation](../../infrastructure/netbird.md#permission-revocation), and [appliance permissions](../../infrastructure/netbird.md#shared-appliance-permissions); [DNS](../../infrastructure/dns.md) covers name resolution.

## Starting point

Fresh start, per the [starting-point decision](https://github.com/mia-cx/yggdrasil-spec/issues/14#issuecomment-5848438788). The old management LXC at 10.0.1.4 has been unreachable since at least 2026-09-14. The crash-looping routing DaemonSet was removed in commit 4c960a5 and Argo pruned it. The legacy Service, EndpointSlice, and IngressRoute in `argocd/netbird/netbird.yaml`, plus the `netbird-setup-key` Secret, get replaced during foundation. Every device enrolls again; nothing migrates.

## Stages

1. Foundation: primary NetBird VM on Proxmox (management, signal, relay) with Docker AdGuard Home and the Olympus LAN routing client. Reached through the current public Traefik plus direct guest port 8443 for diagnosis. An independent Hetzner Repair mesh runs alongside.
2. Hecate: NetBird application with an always-consent authorization flow and per-service permission groups. A pilot test account holding every permission creates the JWT-issued NetBird groups on first sign-in.
3. K3s: NetBird operator with four routing pods (two per node) and one canary service on its own private Traefik entrypoint. No NetBird client runs on the K3s nodes: routine node SSH goes through the `olympus-lan` router, recovery through the Repair netstack client (#24). Confirm no leftover `wt0` interface or firewall rules from the removed host-network pods.
4. Sync job: the hourly Hecate-to-NetBird job with failure and recovery email.
5. Pilot and stability sign-off, below.
6. Per-service cutovers, below.

Current routes, public DNS, and existing access stay unchanged through stage 5. Mesh-only canary and test resources are allowed in pilot scope only.

## Pilot and stability sign-off

Devices: Mia's laptop and phone, one Apple TV, and one family member's phone.

Checks:

- Fresh enrollment on every device.
- Reconnect after sleep and after network changes.
- Host and client restarts.
- Home and away reachability.
- Mesh DNS resolution.
- Routing-pod loss.
- Primary Management unavailable: Mia starts or restarts a client away from home and reaches the Repair host without manual promotion. An existing tunnel staying up is not evidence. K3s DNS/ingress and Hecate are also unavailable during this check.
- A TV enrolled with a single-use no-group key gets access only after its peer ID is linked in Hecate and the next hourly sync runs.
- The hourly sync removes a test permission within 24 hours.
- A sync failure email arrives.

Run for 14 days. Self-recovering glitches are acceptable; log and fix anything needing manual intervention. Sign-off requires 7 consecutive days without manual fixes. Sign-off makes services eligible for cutover; it does not migrate them.

## Cutover order

Mia approves each group as one decision, per the [order and rollback decision](https://github.com/mia-cx/yggdrasil-spec/issues/14#issuecomment-5848465635):

1. Prowlarr as canary, then Sonarr, Radarr, Lidarr, Readarr, SABnzbd, qBittorrent, Tdarr, Tunarr.
2. Longhorn, ArgoCD, Proxmox. kubectl and Repair remain recovery paths.
3. Pelican and Hermes: Wings browser WebSockets and signed transfers, the SFTP alias, and Hermes callbacks per the [routing contract](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743163099).
4. Seerr.
5. Jellyfin.

## Per-service cutover checklist

Readiness, before approval:

- Intended users are enrolled and hold the permission; the Hecate group is reflected in the NetBird group.
- Hecate or native sign-in works through the private route, including native clients where relevant.
- The service's own private Traefik entrypoint port, ClusterIP Service, NetBird resource, and policy exist. A permitted test account connects; an account without the permission cannot.
- The exact-name private DNS answer resolves on mesh clients. TLS is valid and certificate renewal works on the private entrypoint.
- Machine paths (webhooks, APIs, workload egress) are inventoried with replacements.

Cutover, as one change per service:

- Enable the private DNS answer for mesh clients.
- Point public DNS for the hostname to the Janus page.
- Remove the hostname's routes from the current Traefik.
- Restrict the backend so only the private Traefik entrypoint and declared machine clients reach it; no NodePort, LoadBalancer, or direct pod path.

Acceptance, after cutover:

- Permitted users work on mesh at home and away, including native apps.
- Off mesh: the Janus page. Direct LAN IP, NodePort, pod IP, and other Traefik listeners refuse.
- Removing a test account's permission ends access within 24 hours; other services and users stay unaffected.
- Unrelated public services (Immich, Nextcloud, Vaultwarden, OpenSpeedTest, Hecate, NetBird) and their certificates stay unchanged.

Jellyfin adds native playback on phones and Apple TV, owner-cascade to TVs, and proof that another household's playback continues.

## Rollback

Pre-cutover coexistence is deliberate; old routes stay until each service moves. After cutover, fix forward: the service stays mesh-only while broken. Reopening its public route is a Mia-approved revert for that one service. There is no automatic fallback.

## After the last cutover

Retire the legacy DNS VIP 10.0.128.3 only after auditing its consumers and giving them replacement paths, per the [DNS/ingress resolution](https://github.com/mia-cx/yggdrasil-spec/issues/10#issuecomment-5742199940).

## Follow-ups

These stay open until the hardware exists. They are outside this plan.

- A future site's inventory, WAN quality and workloads may need more addressing and placement decisions.
- Migration details for the replacement router and new site equipment wait until that hardware is chosen.
- Device and service reviews may surface more client exceptions or operational needs.
