---
title: Netbird
---

# Netbird

## Planning status

This page contains legacy LXC and wildcard-DNS setup notes. The [accepted DNS/ingress decision](https://github.com/mia-cx/yggdrasil-spec/issues/10#issuecomment-5742199940) selects a primary VM with a separate LAN routing client. Hecate and NetBird stay public.

Explicit private records and resource routes replace the wildcard forwarding below only as services migrate. Keep current Traefik and existing access working during NetBird setup. Each service needs its own readiness checks and approved cutover; the older setup steps are migration reference only.

The same VM hosts Dockerized AdGuard Home for human-device DNS filtering, with a malware-blocking outage fallback. Service, bootstrap, and Repair DNS remain independent and unfiltered. Deployed; see [AdGuard DNS](#adguard-dns).

The primary NetBird VM (`yggdrasil-olympus-1`, 10.0.1.4) serves the mesh at `https://netbird.mia.cx`.

## Olympus LAN route

Deployed: a `netbird-router` client container on `yggdrasil-olympus-1` routes the mesh into the 10.0.0.0/16 LAN through the NetBird Network resource `olympus-lan`, with masquerade so LAN devices see VM-local traffic.

Access is granted only by the `olympus-lan` policy, whose source group is the JWT-issued `svc-lan`. The primary mesh has no `Default` policy: network resources are reachable only through policies that target them. Operations are in the [host README](https://github.com/mia-cx/yggdrasil-spec/blob/main/hosts/yggdrasil-olympus-1/README.md#lan-routing-client).

## AdGuard DNS

Deployed: an AdGuard Home container shares the `olympus-dns` sidecar peer's network namespace, so its `:53` answers on the peer's mesh address with no host DNS port. The NetBird nameserver group `adguard` (primary, all domains) is distributed only to the JWT-issued `netbird-enroll`. Servers, routers and other service peers always enroll with setup keys, never with SSO, so they never carry `netbird-enroll`: group propagation copies a signing-in user's JWT groups onto the peer, which would give a server the filter and every `netbird-enroll` grant.

The outage fallback is the second nameserver _inside the same group_ (`1.1.1.2`, Cloudflare's malware-blocking resolver; ads are not blocked during an outage): NetBird 0.79 tries a group's nameservers in order and fails over only on errors, while two nameserver groups covering the same domain race in parallel — a second group would bypass filtering. Private zones stay NetBird DNS records. Operations are in the [host README](https://github.com/mia-cx/yggdrasil-spec/blob/main/hosts/yggdrasil-olympus-1/README.md#adguard-dns-for-human-devices).

## Accepted K3s integration

The [K3s integration resolution](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743564646) separates node maintenance, application routing, and recovery:

| Role                     | Accepted target                                                                                                                                                 |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cluster routing          | Four operator-managed routing pods across the current two nodes, targeting an even spread. Standard equal-priority pool; no locality or primary/standby tuning. |
| Node maintenance         | A persistent OS-level primary client on each K3s host, independent of pod scheduling.                                                                           |
| Workload connections     | Explicit NetworkResource and NetworkEgress paths, with consumer policy and native application permissions. Node enrollment must not grant implicit pod access.  |
| Selected dual-mesh hosts | Normal primary client plus a separate unprivileged Repair netstack service. Separate state, sockets, and ports; host DNS stays independent.                     |

Ordinary pods keep Kubernetes DNS. Applications needing private names get explicit resolver paths without taking over host-wide or Repair DNS. The resolution links the source evidence and required runtime checks.

Prove NetBird stability with a canary/client pilot and obtain Mia's sign-off before restricting production access. Keep current Traefik, DNS, and service routes working throughout that phase. Coordinate any legacy host-network client replacement before starting an OS-level kernel client on the same node.

The overview and setup sections below remain legacy reference. The accepted plan is not a deployed configuration.

## Accepted enrollment boundaries

The [enrollment decision](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5813024832) records three accepted choices. These remain planning targets until the pilot verifies them.

1. Applications use native Hecate SSO where supported. Reuse its browser session and automatic OAuth entry where available. A fresh browser authenticates. Preserve public Immich, Nextcloud, and Vaultwarden access; vault unlock remains separate.
2. Authorized users enroll their own personal devices without waiting for Mia. The logged-in user confirms enrollment where supported. Their existing grants determine connectivity; enrollment grants no additional service permissions or administrative rights.
3. Shared TVs use restricted appliance identities enrolled through single-use setup keys that carry no auto-groups and expire after 24 hours. Their [service permissions](#shared-appliance-permissions) inherit only the allowed subset of their owner's current grants. Jellyfin identifies the viewer separately.

Hecate's [Consent stage](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/consent/) supports **Always require consent**. Use a NetBird-specific authorization flow and consent stage for this confirmation. Ordinary application SSO keeps its existing flows. The NetBird flow can also prompt during dashboard authorization or interactive reauthentication. The NetBird flow and consent stage now exist in the Authentik blueprint.

This is consent to NetBird authorization during enrollment. It does not depend on NetBird's Cloud-only peer-approval feature. The standard Hecate prompt identifies the application, not the device's hardware identity.

Verify each supported desktop/mobile enrollment path through the selected NetBird integration. Test existing Hecate sessions, declined enrollment, denied enrollment permission, account mismatches, ordinary reconnects, and TV access limits. Source support alone does not prove these flows work in the deployed versions.

The lifecycle ticket is [resolved](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5848385171); the per-service network cutoff covers application sessions, and public apps are out of scope. Existing production access stays available through the NetBird stability pilot.

## Shared appliance permissions

Mia chose [owner-linked TV permissions](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5816269998). Each TV has a main user as its owner. Its effective service permissions equal the intersection of the owner's current effective permissions and the TV's allowed service permissions.

For example, a TV allowed `svc-jellyfin` receives that grant only while its owner has it. The owner's infrastructure permissions stay outside that allowlist. Removing the owner's Jellyfin grant automatically removes it from their TVs too. A disabled or deleted owner provides no inherited service access. The cutoff affects everyone using those TVs; other authorized devices and households retain access.

Jellyfin viewer switching does not change the owner or the TV's network permissions. Appliance grants must stay within the owner and allowlist limits throughout their lifecycle; an enrollment-time copy is insufficient.

The inspected building blocks do not establish this relationship on their own:

- [NetBird user group propagation](https://docs.netbird.io/manage/settings/groups) applies user group changes to owned peers. The [v0.78.1 update path](https://github.com/netbirdio/netbird/blob/v0.78.1/management/server/user.go) adds and removes changed auto-groups across those peers without a per-TV permission cap.
- [Setup-key auto-groups](https://docs.netbird.io/manage/peers/register-machines-using-setup-keys) apply to newly enrolled peers. Changing the key's groups does not update existing peers.
- [Authentik 2026.8.1 group hierarchy](https://github.com/goauthentik/authentik/blob/version/2026.8.1/authentik/core/models.py) supplies ancestor group membership. It does not itself define a parent-user permission ceiling.

TV owners and allowlists live in Hecate. Each TV is a Hecate service account; its allowlist is ordinary membership in permission groups such as `svc-jellyfin`, and the account stores its owner and its NetBird peer ID. A TV enrolls with a [single-use setup key](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5848385171) that carries no auto-groups and expires after 24 hours. Mia enters the peer ID in the service account after enrollment, and the next hourly sync grants access; until then the TV sits on the mesh but reaches nothing. The [hourly sync job](#permission-revocation) sets each TV's NetBird groups to the intersection of its owner's current permissions and the TV allowlist. Before cutover, verify that new requests from every owned TV fail within 24 hours of owner grant removal. Test stale appliance groups, owner deactivation/deletion, and an owner gaining unrelated infrastructure permissions. No case may leave the TV with service access beyond its owner or allowlist. Verify another household's playback continues.

## Personal-device renewal

Mia approved [30-day NetBird SSO renewal](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5813766128) for personal laptops and phones. Plan **Peer Session Expiration** at 30 days (720 hours). This governs the primary-mesh peer login, separately from application cookies, Hecate browser sessions, and [permission revocation](#permission-revocation).

[NetBird's expiry setting](https://docs.netbird.io/manage/settings/enforce-periodic-user-authentication) applies to interactive SSO peers; setup-key peers are exempt. Shared TVs and infrastructure keep their separate credential lifecycle. Repair remains independent of a fresh Hecate login.

Leave the separate **Require login after disconnect** option off for ordinary personal devices. Test that unexpired devices reconnect without extra login prompts and expired devices require Hecate authorization. A valid Hecate browser session may satisfy authentication during renewal. Exercise expiry only with isolated test peers or accounts; changing account-wide settings can disconnect existing users.

## Hecate outages

Retain [default NetBird behavior](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5814922222): existing, unexpired peers keep working when Hecate is unavailable. New enrollment and expired peers wait for Hecate authorization. The 30-day interval still applies; an outage does not extend it. Repair stays independent.

Verify this behavior during the pilot. It does not establish availability of every application's own authentication path during a Hecate outage.

## Repair mesh and external relay

A Hetzner VPS (`yggdrasil-repair-1`, `178.105.231.90`) runs an independent NetBird stack for the Repair mesh at `netbird-repair.mia.cx`: combined `netbird-server` (Management, Signal, embedded Relay + STUN on UDP 3478, embedded IdP with a local admin), the dashboard, and Traefik with Let's Encrypt HTTP-01. It depends on nothing at home: no Hecate, no cluster, no LAN.

The same VPS also runs a standalone `netbirdio/relay` for the primary mesh: `rels://netbird-relay.mia.cx:443` (WebSocket relay through Traefik) plus STUN on UDP 3479. The two roles share only the host; the Repair mesh uses its own embedded relay, and the only shared secret is `NETBIRD_RELAY_AUTH_SECRET` in each host's `/opt/netbird/.env`.

Host details live in `hosts/yggdrasil-repair-1/README.md` (stack, secrets, backups, device enrollment) and `hosts/yggdrasil-olympus-1/README.md` (external relay rotation). The VPS, its IPs, firewall, and DNS records are managed by `terraform/repair` (OpenTofu); rebuilds are explicit `tofu apply -replace=hcloud_server.repair`.

Selected hosts run an independent Repair client: `netbird-repair.service`, one unprivileged netstack-mode daemon per host enrolled to the Repair mesh. Local forwarding maps the host's Repair address to loopback, so the mesh policy's TCP 22 reaches `sshd` on `127.0.0.1` — the recovery path when the primary mesh or LAN is broken. It writes no kernel firewall rules, creates no interfaces, and leaves host DNS alone, which is what makes it safe on the K3s nodes. Install, rotate, remove, and the per-host table live in `hosts/repair-clients/README.md`.

## Hecate permission groups

Every private service has a `svc-<service>` group in Hecate: `svc-prowlarr`, `svc-sonarr`, `svc-radarr`, `svc-lidarr`, `svc-readarr`, `svc-sabnzbd`, `svc-qbittorrent`, `svc-tdarr`, `svc-tunarr`, `svc-longhorn`, `svc-argocd`, `svc-proxmox`, `svc-pelican`, `svc-hermes`, `svc-seerr`, `svc-jellyfin`, `svc-lan`, `svc-ssh`, and `svc-canary`. The `netbird-enroll` group is the enrollment permission; the NetBird application requires it.

Two role presets assign permissions in one step. A member inherits every parent group, so a role's parents are the permissions it grants. `role-admin` parents are every `svc-*` group plus `netbird-enroll`. `role-family` parents are `svc-jellyfin`, `svc-seerr`, and `netbird-enroll`.

The NetBird profile scope emits a `groups` claim with only these permission names. NetBird never sees `role-*` presets or other Hecate groups, and no permission grants admin inside an application. NetBird creates each name as a JWT-issued group the first time a user holding it signs in; never create these groups through the NetBird API or dashboard. The hourly sync job edits membership only.

The blueprint at `argocd/authentik/netbird-blueprint.yaml` defines every group and preset. The `Hecate login` section in `hosts/yggdrasil-olympus-1/README.md` covers recreating the connector and re-seeding the JWT-issued groups after a rebuild.

## Permission revocation

Mia approved a [24-hour revocation bound](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5848158959) for NetBird access to private services, replacing the earlier immediate-revocation requirement. After a permission removal in Hecate, running streams and sessions may finish, but new requests must fail within 24 hours. Unrelated grants and other users' access stay intact.

Paid NetBird IdP Sync is out of scope; Community Edition syncs JWT groups only at sign-in. An hourly scheduled job in K3s covers what sign-in sync misses. It reads each user's effective permissions from Hecate and sets their NetBird groups through the Management API. User group propagation then applies them to all owned peers. For each TV it applies the intersection of the owner's current permissions and the TV's allowlist. The same job handles grants and removals.

TV owners and allowlists live in Hecate. This repository holds only the job's code and settings, never personal data such as names, emails, or device-to-person mappings.

The [sync design](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5848276326) keeps JWT group sync on: new grants apply at the next sign-in, while the job covers removals between sign-ins and TVs, which never sign in. Both paths derive from Hecate and converge. NetBird v0.78.1 bounds both sides: sign-in sync adds users only to JWT-issued groups, silently skips same-name API and dashboard groups, removes only JWT-issued groups, and propagates changes to the user's own peers when group propagation is enabled. PAT-authenticated requests never trigger it. The job therefore never creates access groups; it edits membership of groups that sign-in sync created. A sign-in from an account holding each permission bootstraps every access group, and an account in `role-admin` creates them all.

TV peers have no owning user, so the job sets their group membership directly and sign-in sync never touches them. Hecate still decides who may enroll. The job reports failures by email through the existing SMTP relay (email-oauth2-proxy): one message when runs start failing, one on recovery.

Enforcement is the [per-service network cutoff](#per-service-network-destinations) below: removing a permission cuts NetBird access to that one service within the hourly sync. Before cutover, test old credentials, reconnects, stale group claims, and unaffected users on each private service; include shared TVs where relevant. Record removal and enforcement times; expose failed or delayed enforcement instead of reporting success.

Public Immich, Nextcloud, and Vaultwarden are [out of scope](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5848330338). They stay reachable without NetBird, and their sign-in, sessions, and revocation are Hecate matters with no NetBird dependency. The bound and sync job cover NetBird access only. Existing production access stays in place until NetBird stability sign-off and that service's approved cutover.

### Per-service network destinations

Every private service gets its own enforceable network destination, generalizing the Jellyfin contract below. Each mesh-only service gets a private Traefik entrypoint on its own port, its own ClusterIP Service, and its own published NetBird resource. A policy admits only that service's permission group. Traefik keeps terminating TLS and existing URLs stay unchanged; no other entrypoint answers for that hostname.

The private instance is deployed as `traefik-internal` with the canary service, per the [canary isolation contract](https://github.com/mia-cx/yggdrasil-spec/blob/main/argocd/traefik-internal/README.md).

The dedicated port is what makes services distinguishable: kube-proxy maps every ClusterIP to the pod's target port, so two Services reaching Traefik on the same port are indistinguishable. Removing a permission cuts network access to that one service within the hourly sync; application sessions and native tokens may stay intact behind the cutoff.

### Jellyfin network cutoff

Mia [clarified the enforcement boundary](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5816141470): remove the affected peers' Jellyfin access through NetBird. Jellyfin credentials and sessions can remain intact behind the blocked network path. Jellyfin-specific account or token revocation is not required for this path.

Remove service access while preserving the peer's unrelated grants. A shared private Traefik IP and HTTPS port cannot distinguish service permissions; a different hostname or resource label alone is insufficient. Jellyfin uses its own destination under the [per-service rule](#per-service-network-destinations); no other permitted listener may serve it, and the existing Jellyfin URL stays.

Before cutover, prove these outcomes on isolated pilot resources:

| Check                                                                | Required outcome                                                                                           |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Remove effective `svc-jellyfin`                                      | Every affected peer loses Jellyfin access within 24 hours, without waiting for sign-in or 30-day renewal.  |
| Retry with old tokens, reconnect, or use another ingress destination | Jellyfin remains unreachable, including through public, direct LAN, and other permitted private listeners. |
| Use an unrelated service or a different authorized peer              | Unrelated grants and other users' access remain usable.                                                    |

Record permission-removal and enforcement times. Validate every routing peer and failover path used by the pilot; runtime behavior remains unproven.

Shared TVs follow the [owner-linked permission rule](#shared-appliance-permissions). Removing an owner's Jellyfin grant also revokes that grant from their TVs. This cuts off Jellyfin for everyone using those TVs; individual viewer revocation inside an otherwise authorized TV is not required by this plan.

Public Immich, Nextcloud, and Vaultwarden stay outside the NetBird plan; their sign-in, sessions, and revocation remain Hecate matters. The hourly sync job propagates removals without waiting for login. This network cutoff does not require the previously proposed Jellyfin account/token automation.

### Revocation source checks

The accepted 24-hour bound supersedes the immediate-revocation requirement behind these checks; the stream-termination findings below remain as source evidence and no longer gate cutover.

The [source review](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5814998437) uses Jellyfin v12.0, matching the repository's requested image tag. It does not verify the running image digest.

Jellyfin's [request authentication](https://github.com/jellyfin/jellyfin/blob/v12.0/Emby.Server.Implementations/HttpServer/Security/AuthService.cs) rejects disabled users. Its [session manager](https://github.com/jellyfin/jellyfin/blob/v12.0/Emby.Server.Implementations/Session/SessionManager.cs) can revoke device credentials, but the playback Stop command sends a message to the client. The [direct-file response](https://github.com/jellyfin/jellyfin/blob/v12.0/Jellyfin.Api/Helpers/FileStreamResponseHelpers.cs) uses a range-enabled `PhysicalFileResult`. These controls do not establish immediate cancellation of an already-started response.

These application controls are background evidence. The chosen Jellyfin boundary is the [NetBird cutoff](#jellyfin-network-cutoff), whose established-flow behavior still needs runtime proof.

Hecate's [membership audit handler](https://github.com/goauthentik/authentik/blob/version/2026.8.1/authentik/events/middleware.py) includes `pre_remove` events. Its [notification tasks](https://github.com/goauthentik/authentik/blob/version/2026.8.1/authentik/events/tasks.py) run asynchronously. An event payload is not a post-commit permission snapshot; verify current effective membership and event coverage before using notifications for revocation.

Permission editing remains in Hecate. The propagation mechanism and NetBird enforcement of established flows remain unresolved. No custom application-revocation component is approved.

## Overview

| Property | Value              |
| -------- | ------------------ |
| Type     | LXC                |
| IP       | 10.0.1.4           |
| VMID     | 1004               |
| Template | debian-12-standard |
| vCPUs    | 1-2                |
| RAM      | 512MB-1GB          |
| Disk     | 8GB                |

WireGuard overlay network management server, deployed in a dedicated LXC independent of K3s. Provides secure remote access to all internal services via domain-based routing.

**Why LXC?**

- Management stays up even if K3s is down
- Existing WireGuard tunnels survive management outage
- Can still access infrastructure to fix K3s

## Prerequisites

- Proxmox LXC created with the specs above
- [Authentik](./authentik.md) running and accessible for OIDC

## Setup

```bash
apt update && apt install -y docker.io docker-compose
mkdir -p /opt/netbird && cd /opt/netbird

# Download docker-compose from Netbird self-hosted docs
# Configure with Authentik OIDC
```

### Authentik OIDC

```yaml
# In Netbird management config
oidc:
  issuer: https://auth.yggdrasil.mia.cx/application/o/netbird/
  clientId: netbird
  clientSecret: <from-authentik>
```

### K3s routing pods

The `netbird-operator` ArgoCD app deploys chart 0.8.0 and the `k8s-routers` NetworkRouter: four routing pods, spread two per node by a `DoNotSchedule` topology constraint. K3s hosts run no NetBird client: the client's nftables rules crash k3s's bundled kube-router netpol controller ([kube-router#1788](https://github.com/cloudnativelabs/kube-router/issues/1788), [k3s#11493](https://github.com/k3s-io/k3s/issues/11493)), and with two etcd members one crashing node takes the cluster down. SSH to nodes instead goes through the `olympus-lan` router: resources `hydra-olympus-1-ssh`/`hydra-olympus-2-ssh` sit in group `k3s-nodes-ssh`, and policy `ssh-to-k3s-nodes` grants `svc-ssh` TCP 22 only. `svc-lan` is full Olympus LAN access for administrators (only `role-admin` carries it), so it includes node SSH; `svc-ssh` grants node SSH without the rest of the LAN. The independent recovery path is the unprivileged Repair netstack client from the dual-mesh design, which writes no kernel firewall rules ([#24](https://github.com/mia-cx/yggdrasil-spec/issues/24)). See [argocd/netbird-operator/README.md](https://github.com/mia-cx/yggdrasil-spec/blob/main/argocd/netbird-operator/README.md).

## Configuration

### Networks (Service Access)

Uses Netbird's [Networks](https://docs.netbird.io/manage/networks) feature with wildcard domain resources. Netbird only routes traffic for matching domains -- users can't IP-scan the LAN, and multi-site scales automatically.

**1. Enable DNS wildcard routing:**

Settings → Networks → Enable DNS wildcard routing

**2. Create network:**

| Setting | Value       |
| ------- | ----------- |
| Name    | `Yggdrasil` |

**3. Add routing peers:**

| Setting    | Value                                 |
| ---------- | ------------------------------------- |
| Group      | Exit node auto-group (from setup key) |
| Masquerade | Enabled                               |

**4. Add wildcard domain resources:**

| Resource             | Group                |
| -------------------- | -------------------- |
| `*.mia.cx`           | `yggdrasil-services` |
| `*.yggdrasil.mia.cx` | `yggdrasil-services` |

**5. Access control policy:**

| Setting     | Value                           |
| ----------- | ------------------------------- |
| Source      | `All` (or specific user groups) |
| Destination | `yggdrasil-services`            |
| Protocol    | All                             |

### DNS Resolution (CoreDNS Custom Zone)

Exit nodes use `dnsPolicy: ClusterFirstWithHostNet`, so they query K3s CoreDNS. A `coredns-custom` ConfigMap resolves `*.mia.cx` to the Traefik VIP (`10.0.128.2`):

```bash
kubectl apply -f argocd/k3s/coredns-custom.yaml
```

Auto-synced by ArgoCD (`k3s-base` Application). Each site sets its own Traefik VIP in the ConfigMap -- multi-site just works.

### Split-Horizon DNS

| Context               | Resolution                                                 |
| --------------------- | ---------------------------------------------------------- |
| External (Cloudflare) | `*.yggdrasil.mia.cx` → Cloudflare Workers (Janus)          |
| Internal (Netbird)    | `*.mia.cx` / `*.yggdrasil.mia.cx` → `10.0.128.2` (Traefik) |

See also: [DNS](./dns.md)

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                      Internet                            │
└──────────────────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────┐
│               Netbird Management (10.0.1.4)              │
│                                                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐  │
│  │ STUN/TURN   │    │ Signal      │    │ Management  │  │
│  └─────────────┘    └─────────────┘    └─────────────┘  │
│                             │                            │
│                   Authentik OIDC                          │
└──────────────────────────────────────────────────────────┘
                             │
             ┌───────────────┼───────────────┐
             ▼               ▼               ▼
       ┌──────────┐   ┌──────────┐   ┌──────────┐
       │ Exit     │   │ Exit     │   │ Client   │
       │ Node 1   │   │ Node 2   │   │ Device   │
       │ (K3s)    │   │ (K3s)    │   │          │
       └──────────┘   └──────────┘   └──────────┘
```

**How traffic flows:**

1. Client queries `jellyfin.mia.cx` → Netbird intercepts via domain resource
2. Routed to nearest exit node (routing peer) in the `Yggdrasil` network
3. Exit node resolves via K3s CoreDNS → `10.0.128.2` (Traefik VIP)
4. Exit node forwards traffic to Traefik → routes to service pod

## Verification

```bash
# Check routing pods
kubectl get pods -n netbird-operator

# Test from a Netbird client
nslookup jellyfin.yggdrasil.mia.cx
curl -I https://jellyfin.yggdrasil.mia.cx
```
