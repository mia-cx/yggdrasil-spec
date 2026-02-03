---
title: DNS Architecture
---

# DNS Architecture

Split-horizon DNS provides different resolution based on network context.

## Overview

```
External (Cloudflare):
  *.yggdrasil.mia.cx → Cloudflare Workers (Janus landing pages)

Internal (Netbird DNS):
  *.yggdrasil.mia.cx → Internal IPs (100.64.x.x overlay or 10.0.x.x)
```

## How It Works

1. **Not on Netbird:** DNS resolves to Cloudflare, which serves Janus landing pages
2. **On Netbird:** Netbird DNS takes precedence, resolves to internal IPs

## Netbird DNS Config

- Nameserver group pointing to internal DNS (CoreDNS/AdGuard in K3s)
- Match domain: `yggdrasil.mia.cx`
- When connected to Netbird, internal DNS takes precedence

## Internal DNS Records

CoreDNS or AdGuard in K3s:

| Record | IP | Purpose |
|--------|-----|---------|
| hydra.yggdrasil.mia.cx | 10.0.128.1 | K3s API VIP |
| traefik.yggdrasil.mia.cx | 10.0.128.2 | Traefik VIP |
| jellyfin.yggdrasil.mia.cx | 10.0.128.2 | Jellyfin (via Traefik) |
| auth.yggdrasil.mia.cx | 10.0.128.2 | Authentik (via Traefik) |
| *.yggdrasil.mia.cx | 10.0.128.2 | Wildcard to Traefik |

## Cloudflare DNS Records

| Record | Type | Value |
|--------|------|-------|
| *.yggdrasil.mia.cx | CNAME | janus.workers.dev (or custom) |

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     User Device                             │
└─────────────────────────────────────────────────────────────┘
                              │
                   jellyfin.yggdrasil.mia.cx
                              │
              ┌───────────────┴───────────────┐
              │                               │
     Not on Netbird                    On Netbird
              │                               │
              ▼                               ▼
┌─────────────────────────┐   ┌─────────────────────────────┐
│ Cloudflare DNS          │   │ Netbird DNS                 │
│ → Janus Worker          │   │ → 10.0.128.2 (Traefik)      │
│ → "Connect to Yggdrasil"│   │ → Jellyfin service          │
└─────────────────────────┘   └─────────────────────────────┘
```
