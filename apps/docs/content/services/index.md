---
title: Services
---

# Services

Application services running in the K3s cluster. For platform-level components (Traefik, DNS, Authentik, Netbird), see [Infrastructure](../infrastructure/index.md).

## Application Services

| Service                         | Purpose                                 | SSO Method    |
| ------------------------------- | --------------------------------------- | ------------- |
| [Jellyfin](./jellyfin.md)       | Media streaming                         | OIDC (plugin) |
| [Media Stack](./media-stack.md) | Media automation (Sonarr, Radarr, etc.) | Internal-only |
| [Nextcloud](./nextcloud.md)     | File sync + collaboration               | OIDC          |
| [Vaultwarden](./vaultwarden.md) | Password management                     | Native OIDC   |
| [Pelican](./pelican.md)         | Game servers                            | --            |
| [Janus](./janus.md)             | External landing pages                  | --            |
| Forgejo                         | Git hosting (planned)                   | OIDC          |
| Grafana                         | Monitoring dashboards (planned)         | OIDC          |
| Plausible                       | Analytics (planned)                     | --            |

## Cluster Service Inventory

| Service       | Image                                        | Port | Namespace     | Purpose                   |
| ------------- | -------------------------------------------- | ---- | ------------- | ------------------------- |
| **Media**     |
| Jellyfin      | `docker.io/jellyfin/jellyfin:10`             | 8096 | `media`       | Media streaming           |
| Seerr         | `ghcr.io/seerr-team/seerr:develop`           | 5055 | `media`       | Request/discovery (Jellyfin) |
| Sonarr        | `lscr.io/linuxserver/sonarr:latest`          | 8989 | `media`       | TV automation             |
| Radarr        | `lscr.io/linuxserver/radarr:latest`          | 7878 | `media`       | Movie automation          |
| Lidarr        | `lscr.io/linuxserver/lidarr:latest`          | 8686 | `media`       | Music automation          |
| Readarr       | `docker.io/linuxserver/readarr:develop-0.4.18.2805-ls157` | 8787 | `media`       | Ebook/audiobook automation |
| Prowlarr      | `lscr.io/linuxserver/prowlarr:latest`        | 9696 | `media`       | Indexer management        |
| SABnzbd       | `lscr.io/linuxserver/sabnzbd:latest`         | 8080 | `media`       | Usenet downloader         |
| qBittorrent   | `lscr.io/linuxserver/qbittorrent:latest`     | 8080 | `media`       | Torrent client            |
| FlareSolverr  | `ghcr.io/flaresolverr/flaresolverr:latest`   | 8191 | `media`       | Cloudflare bypass         |
| Privoxy       | `docker.io/vimagick/privoxy:latest`          | 8118 | `media`       | HTTP proxy                |
| Prefetcharr   | `docker.io/phueber/prefetcharr:latest`       | --   | `media`       | Prefetch next seasons     |
| Tdarr         | `docker.io/haveagitgat/tdarr:latest`         | 8265 | `media`       | Transcode automation      |
| **Apps**      |
| Nextcloud     | `nextcloud/nextcloud:32-apache`              | 80   | `nextcloud`   | File sync + collaboration |
| Immich Server | `ghcr.io/immich-app/immich-server:v2.5.5`    | 2283 | `immich`      | Photo management          |
| Immich ML     | `ghcr.io/immich-app/immich-machine-learning` | 3003 | `immich`      | Photo ML inference        |
| Vaultwarden   | `vaultwarden/server:1.35.4`                  | 80   | `vaultwarden` | Password management       |
| Pelican Panel | --                                           | 80   | `pelican`     | Game server management    |

## Common Patterns

**For each service:**

1. Create namespace + Longhorn PVC
2. Customize Helm values or write manifests
3. Backup/restore data from old Docker Compose
4. Create IngressRoute, update DNS
5. Decommission old container

**Storage tiers:**

| Tier            | Type          | Use Case                              |
| --------------- | ------------- | ------------------------------------- |
| Longhorn        | Block (local) | Databases, configs, small persistence |
| NFS (media)     | MergerFS pool | Bulk media storage (~29Ti)            |
| NFS (critical)  | NVMe          | Fast storage for databases, configs   |
| NFS (downloads) | Old server    | Download staging                      |
