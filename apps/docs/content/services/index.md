---
title: Services
---

# Services

## Core Services

| Service | Purpose | SSO |
|---------|---------|-----|
| [DNS](./dns.md) | Split-horizon resolution | - |
| [Traefik](./traefik.md) | Ingress + TLS | Middleware |
| [Janus](./janus.md) | External landing pages | - |

## Application Services

| Service | Purpose | SSO Method |
|---------|---------|------------|
| [Jellyfin](./jellyfin.md) | Media streaming | OIDC (plugin) |
| [Pelican](./pelican.md) | Game servers | - |
| Nextcloud | File sync + collaboration | OIDC |
| Bitwarden | Password management | - |
| Forgejo | Git hosting | OIDC |
| Grafana | Monitoring dashboards | OIDC |
| Sonarr/Radarr | Media automation | Proxy auth |
| Plausible | Analytics | - |

## Service Migration Order

1. **Jellyfin** - Practice migration with SSO
2. **Nextcloud** - Critical, needs careful data migration
3. **Bitwarden** - Critical, official Helm chart
4. **Plausible** - Analytics
5. **Media stack** - Sonarr, Radarr, SABnzbd, qBittorrent
6. **Pelican** - Game servers
7. **Forgejo** - Git hosting

## Common Patterns

### For each service:

1. Create namespace + Longhorn PVC
2. Customize Helm values or write manifests
3. Backup/restore data from old Docker Compose
4. Create IngressRoute, update DNS
5. Decommission old container

### Storage

- **Longhorn:** Small, block-level persistence (databases, configs)
- **NFS (media):** Bulk media storage (32TB MergerFS pool)
- **NFS (critical):** Fast NVMe storage (databases, configs)
- **NFS (downloads):** Download staging from old server
