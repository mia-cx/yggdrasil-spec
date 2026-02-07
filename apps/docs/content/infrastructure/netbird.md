---
title: Netbird
---

# Netbird

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

### Exit Nodes (K3s DaemonSet)

Exit nodes run in K3s for redundancy across nodes. Create a setup key in the Netbird admin UI (Setup Keys → auto-groups for exit node group).

```bash
kubectl create secret generic netbird-setup-key \
  -n netbird \
  --from-literal=key="YOUR_SETUP_KEY"

kubectl apply -f argocd/netbird/exit-node-daemonset.yaml
```

Exit nodes connect to management server at `https://netbird.mia.cx` (10.0.1.4).

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
# Check exit node pods
kubectl get pods -n netbird

# Test from a Netbird client
nslookup jellyfin.yggdrasil.mia.cx
curl -I https://jellyfin.yggdrasil.mia.cx
```
