---
title: DNS
---

# DNS

## Accepted target

The [accepted DNS/ingress decision](https://github.com/mia-cx/yggdrasil-spec/issues/10#issuecomment-5742199940) replaces the legacy setup below through gradual per-service cutovers. This is an approved plan, not a deployed configuration.

| Consumer after a private service's cutover  | Private service name                                       | Public names                             |
| ------------------------------------------- | ---------------------------------------------------------- | ---------------------------------------- |
| NetBird-connected human device              | Explicit private alias and resource route                  | Public records through AdGuard filtering |
| NetBird-connected service peer              | Explicit records and authorized machine path where needed  | Unfiltered upstream DNS                  |
| Disconnected device, including the home LAN | Janus connection page                                      | Existing public DNS                      |
| Kubernetes workload                         | Local Service DNS, or an approved exact HTTPS-name mapping | Unfiltered upstream DNS                  |

Keep existing service URLs. NetBird Custom Zones hold explicit aliases, while the Kubernetes operator owns generated Service records. Private web traffic reaches a separate ClusterIP-only Traefik through cluster routing peers. DNS does not enforce access; routing, workload policy, and application permissions do.

Keep normal Kubernetes CoreDNS at `10.43.0.10`. Retire the extra DNS VIP `10.0.128.3`, both competing DNS Services, and whole-zone overrides only after consumer migration. Hecate, NetBird, and unrelated public services retain public DNS.

### Human DNS filtering

AdGuard Home runs in Docker on the primary NetBird management VM, outside K3s. A dedicated NetBird sidecar provides its planned mesh entrance without publishing host DNS ports. Human-device groups receive filtered DNS with unfiltered outage fallback. Services, infrastructure bootstrap, and Repair use independent unfiltered DNS. Private records remain in NetBird, not AdGuard.

### Node and application resolution

The [accepted K3s integration](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743564646) keeps ordinary pods on CoreDNS and uses exact-name mappings where canonical HTTPS URLs must be retained. Backend egress targets identify the actual mesh host, not a frontend alias pointing back to Traefik.

Keep maintenance-client enrollment from taking over host DNS. In inspected NetBird client v0.78.1, client-side `--disable-dns` leaves the local resolver available while disabling OS configuration changes. Management-side DNS disablement is different. [Service DNS evidence](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743310500) covers explicit application resolver views and their canary checks. Host bootstrap and Repair retain independent resolution.

### Migration boundary

First prove NetBird stability with a canary/client pilot and obtain Mia's sign-off before any production service requires the mesh. Leave current Traefik, its routes, public DNS, and required legacy DNS paths unchanged through that phase. Installing NetBird does not authorize switching everyone's DNS or replacing service pages with Janus.

Move one service at a time when its users and native clients are ready, Hecate/native authentication works, and Mia approves its cutover. Coordinate private DNS, Janus, public-origin removal, and backend restrictions for that service. Other services retain their existing access. After a private cutover, rollback must not silently restore public origin access.

The resolution defines record-type behavior, certificates, bootstrap, and acceptance checks. [Choose migration order and acceptance checks](https://github.com/mia-cx/yggdrasil-spec/issues/14) plans their sequence. Current manifests remain migration evidence, not instructions to apply the target now.

## Legacy overview

The remaining sections preserve the earlier configuration for migration reference. LAN bypasses and wildcard DNS forwarding below are not the replacement design or instructions to deploy it.

| Property | Value                                             |
| -------- | ------------------------------------------------- |
| Type     | Multi-layer (Cloudflare + Netbird + CoreDNS)      |
| External | `*.yggdrasil.mia.cx` → Cloudflare Workers (Janus) |
| Internal | `*.mia.cx` → 10.0.128.2 (Traefik VIP via CoreDNS) |

Split-horizon DNS provides different resolution depending on whether the client is on Netbird or (for LAN) using a DNS server that returns the Traefik VIP.

## Legacy LAN access (without NetBird)

When you’re on WiFi at home, your device usually uses the router or public DNS. Those resolve `*.yggdrasil.mia.cx` to the public IP, so traffic goes out and back in and Traefik sees the public IP → **internal-only** returns Forbidden.

To have it work internally from the same network, LAN clients must resolve `*.yggdrasil.mia.cx` to the Traefik VIP **10.0.128.2** so traffic stays local and Traefik sees your LAN IP (e.g. 10.0.1.x).

**Options:**

1. **Router** — If it supports “Local DNS”, “DNS override”, or “Static host”, add `yggdrasil.mia.cx` (or each hostname) → `10.0.128.2`. Then devices that use the router as DNS will get internal resolution.
2. **Pi-hole / AdGuard Home** — Add a DNS rewrite or local record: `*.yggdrasil.mia.cx` → `10.0.128.2`. Point the router’s DHCP DNS to this server so WiFi clients use it.
3. **Netbird on the device** — Install and use Netbird when on WiFi; then DNS goes through the overlay and CoreDNS returns 10.0.128.2.

After LAN DNS returns 10.0.128.2, open `https://radarr.yggdrasil.mia.cx` from the same network; it should hit Traefik with your LAN IP and pass internal-only.

## Legacy NetBird DNS flow

1. **Not on Netbird:** DNS resolves via Cloudflare, which serves Janus landing pages ("Connect to Yggdrasil to access this service")
2. **On Netbird:** Domain resources intercept `*.mia.cx` queries, route through exit nodes, which resolve via K3s CoreDNS to the Traefik VIP

## Legacy architecture

```
┌──────────────────────────────────────────────────────────────┐
│                       User Device                            │
└──────────────────────────────────────────────────────────────┘
                             │
                  jellyfin.yggdrasil.mia.cx
                             │
             ┌───────────────┴───────────────┐
             │                               │
    Not on Netbird                    On Netbird
             │                               │
             ▼                               ▼
┌─────────────────────────┐   ┌──────────────────────────────┐
│ Cloudflare DNS          │   │ Netbird domain resource       │
│ → Janus Worker          │   │ → Exit node (routing peer)    │
│ → "Connect to Yggdrasil"│   │ → K3s CoreDNS → 10.0.128.2   │
└─────────────────────────┘   │ → Traefik → Service           │
                              └──────────────────────────────┘
```

## Legacy setup

### Layer 1 -- Netbird Domain Resources

Wildcard domain resources (`*.mia.cx`, `*.yggdrasil.mia.cx`) in a Netbird Network intercept matching traffic and route it through the nearest exit node. See [Netbird -- Networks](./netbird.md#networks-service-access).

### Layer 2 -- K3s CoreDNS Custom Zone

Exit nodes use `dnsPolicy: ClusterFirstWithHostNet`, so they query K3s CoreDNS. A `coredns-custom` ConfigMap resolves `*.mia.cx` to the Traefik VIP (`10.0.128.2`):

```bash
kubectl apply -f argocd/k3s/coredns-custom.yaml
```

Each site sets its own VIP in the ConfigMap -- multi-site scales automatically. See [Netbird -- DNS Resolution](./netbird.md#dns-resolution-coredns-custom-zone).

### Cloudflare DNS Records

| Record               | Type  | Value              |
| -------------------- | ----- | ------------------ |
| `*.yggdrasil.mia.cx` | CNAME | Janus Worker route |

### Cloudflare DDNS

Dynamic DNS keeps site-specific ingress records updated with the correct public IP. Current single-site records include `olympus.yggdrasil.mia.cx` and `id.mia.cx`; public aliases such as `speedtest.mia.cx` can CNAME through those records.

**Single site:**

```bash
kubectl apply -f argocd/cloudflare-ddns/deployment.yaml
```

**Multi-site (future):** Each site runs its own DDNS pod. Nodes are labeled by site (`topology.kubernetes.io/site=<name>`) and a DaemonSet with topology constraints updates `{site}.yggdrasil.mia.cx` automatically.

```bash
kubectl apply -f argocd/cloudflare-ddns/daemonset.yaml
```

## Legacy verification

```bash
# Test external resolution
dig jellyfin.yggdrasil.mia.cx

# Test internal resolution (from Netbird client)
nslookup jellyfin.yggdrasil.mia.cx

# Check CoreDNS custom config
kubectl get configmap coredns-custom -n kube-system -o yaml
```
