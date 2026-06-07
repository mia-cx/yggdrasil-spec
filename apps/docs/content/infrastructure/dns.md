---
title: DNS
---

# DNS

## Overview

| Property | Value                                             |
| -------- | ------------------------------------------------- |
| Type     | Multi-layer (Cloudflare + Netbird + CoreDNS)      |
| External | `*.yggdrasil.mia.cx` → Cloudflare Workers (Janus) |
| Internal | `*.mia.cx` → 10.0.128.2 (Traefik VIP via CoreDNS) |

Split-horizon DNS provides different resolution depending on whether the client is on Netbird or (for LAN) using a DNS server that returns the Traefik VIP.

## LAN (same network, no Netbird)

When you’re on WiFi at home, your device usually uses the router or public DNS. Those resolve `*.yggdrasil.mia.cx` to the public IP, so traffic goes out and back in and Traefik sees the public IP → **internal-only** returns Forbidden.

To have it work internally from the same network, LAN clients must resolve `*.yggdrasil.mia.cx` to the Traefik VIP **10.0.128.2** so traffic stays local and Traefik sees your LAN IP (e.g. 10.0.1.x).

**Options:**

1. **Router** — If it supports “Local DNS”, “DNS override”, or “Static host”, add `yggdrasil.mia.cx` (or each hostname) → `10.0.128.2`. Then devices that use the router as DNS will get internal resolution.
2. **Pi-hole / AdGuard Home** — Add a DNS rewrite or local record: `*.yggdrasil.mia.cx` → `10.0.128.2`. Point the router’s DHCP DNS to this server so WiFi clients use it.
3. **Netbird on the device** — Install and use Netbird when on WiFi; then DNS goes through the overlay and CoreDNS returns 10.0.128.2.

After LAN DNS returns 10.0.128.2, open `https://radarr.yggdrasil.mia.cx` from the same network; it should hit Traefik with your LAN IP and pass internal-only.

## How It Works (Netbird)

1. **Not on Netbird:** DNS resolves via Cloudflare, which serves Janus landing pages ("Connect to Yggdrasil to access this service")
2. **On Netbird:** Domain resources intercept `*.mia.cx` queries, route through exit nodes, which resolve via K3s CoreDNS to the Traefik VIP

## Architecture

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

## Setup

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

## Verification

```bash
# Test external resolution
dig jellyfin.yggdrasil.mia.cx

# Test internal resolution (from Netbird client)
nslookup jellyfin.yggdrasil.mia.cx

# Check CoreDNS custom config
kubectl get configmap coredns-custom -n kube-system -o yaml
```
