---
title: Netbird LXC
---

# Netbird LXC

WireGuard overlay network management server, deployed in a dedicated LXC independent of K3s.

## Overview

| Property | Value |
|----------|-------|
| IP | 10.0.1.5 |
| VMID | 1005 |
| Template | debian-12-standard |
| vCPUs | 1-2 |
| RAM | 512MB-1GB |
| Disk | 8GB |

## Why LXC?

- **Resilience:** Management stays up even if K3s is down
- **Tunnel survival:** Existing WireGuard tunnels survive management outage
- **Recovery:** Can still access infrastructure to fix K3s

## Installation

```bash
apt update && apt install -y docker.io docker-compose
mkdir -p /opt/netbird && cd /opt/netbird

# Download docker-compose from Netbird self-hosted docs
# Configure with Authentik OIDC
```

## Authentik OIDC Configuration

```yaml
# In Netbird management config
oidc:
  issuer: https://auth.yggdrasil.mia.cx/application/o/netbird/
  clientId: netbird
  clientSecret: <from-authentik>
```

## Exit Nodes (K3s DaemonSet)

Exit nodes run in K3s for redundancy across nodes:

```bash
# Deploy exit node DaemonSet after management is up
kubectl apply -f netbird-exit-node-daemonset.yaml
```

Exit nodes connect to management server at 10.0.1.5.

## DNS Configuration

Netbird provides split-horizon DNS:

| Context | Resolution |
|---------|------------|
| External (Cloudflare) | `*.yggdrasil.mia.cx` → Cloudflare Workers |
| Internal (Netbird) | `*.yggdrasil.mia.cx` → Internal IPs |

### Netbird DNS Settings

- Nameserver group pointing to internal DNS (CoreDNS/AdGuard in K3s)
- Match domain: `yggdrasil.mia.cx`
- When connected to Netbird, internal DNS takes precedence

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Internet                               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│               Netbird Management (10.0.1.5)                 │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │ STUN/TURN   │    │ Signal      │    │ Management  │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│                              │                              │
│                    Authentik OIDC                           │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        ┌──────────┐   ┌──────────┐   ┌──────────┐
        │ Exit     │   │ Exit     │   │ Client   │
        │ Node 1   │   │ Node 2   │   │ Device   │
        │ (K3s)    │   │ (K3s)    │   │          │
        └──────────┘   └──────────┘   └──────────┘
```
