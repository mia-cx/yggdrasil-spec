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

Split-horizon DNS provides different resolution depending on whether the client is connected to the Netbird overlay network.

## How It Works

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

Dynamic DNS keeps site-specific records updated with the correct public IP.

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
