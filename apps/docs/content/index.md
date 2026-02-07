---
title: Yggdrasil
---

# Yggdrasil

Personal homelab infrastructure connecting multiple sites through a unified overlay network.

## What is Yggdrasil?

Named after the Norse world tree that connects all realms, Yggdrasil is the overarching infrastructure spanning:

- **Olympus** -- Primary home site (Greek: seat of the gods)
- **Elysium** -- Secondary site (future)
- **Arcadia** -- Tertiary site (future)

## Core Components

| Component     | Name          | Description                             |
| ------------- | ------------- | --------------------------------------- |
| Orchestration | **Hydra**     | K3s cluster (multi-headed, regenerates) |
| Identity      | **Authentik** | SSO for all services                    |
| Overlay       | **Netbird**   | WireGuard mesh network                  |
| Gateway       | **Janus**     | Landing pages for external users        |
| Ingress       | **Traefik**   | Reverse proxy + TLS                     |

## Domain

All services live under `*.yggdrasil.mia.cx`:

- `auth.yggdrasil.mia.cx` -- Authentik IdP
- `jellyfin.yggdrasil.mia.cx` -- Media streaming
- `cloud.yggdrasil.mia.cx` -- Nextcloud

## Quick Links

- [Architecture Overview](./architecture/index.md) -- hardware, network, design decisions
- [Infrastructure](./infrastructure/index.md) -- Storage LXC, K3s, Authentik, Netbird, Traefik, DNS
- [Services](./services/index.md) -- Jellyfin, Nextcloud, Vaultwarden, media stack, Pelican
- [Operations](./operations/index.md) -- migration plan, runbooks
- [Quick Reference](./reference.md) -- IPs, VMIDs, service URLs
