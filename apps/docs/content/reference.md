---
title: Quick Reference
---

# Quick Reference

At-a-glance lookups. For detailed command recipes, see [Runbooks](./operations/runbooks.md).

## IP Addresses & VMIDs

| Entity         | IP         | VMID |
| -------------- | ---------- | ---- |
| Proxmox host   | 10.0.1.1   | --   |
| Storage LXC    | 10.0.1.2   | 1002 |
| K3s VM         | 10.0.1.3   | 1003 |
| Netbird LXC    | 10.0.1.4   | 1004 |
| Wings VM       | 10.0.1.6   | 1006 |
| Old Server     | 10.0.1.8   | --   |
| Old Server K3s | 10.0.1.9   | 1009 |
| Workstation VM | 10.0.3.1   | 3001 |
| K3s API VIP    | 10.0.128.1 | --   |
| Traefik VIP    | 10.0.128.2 | --   |

**VMID Pattern:** `(3rd_octet * 1000) + last_octet`

## Service URLs

| Service       | URL                                    |
| ------------- | -------------------------------------- |
| Authentik     | `https://id.mia.cx`                    |
| Jellyfin      | `https://jellyfin.yggdrasil.mia.cx`    |
| Nextcloud     | `https://cloud.yggdrasil.mia.cx`       |
| Vaultwarden   | `https://warden.mia.cx`                |
| Proxmox       | `https://10.0.1.1:8006`                |
| Longhorn      | `https://longhorn.yggdrasil.mia.cx`    |
| Grafana       | `https://grafana.yggdrasil.mia.cx`     |
| Seerr         | `https://seerr.yggdrasil.mia.cx`       |
| Sonarr        | `https://sonarr.yggdrasil.mia.cx`      |
| Radarr        | `https://radarr.yggdrasil.mia.cx`      |
| Readarr       | `https://readarr.yggdrasil.mia.cx`     |
| Prowlarr      | `https://prowlarr.yggdrasil.mia.cx`    |
| SABnzbd       | `https://sabnzbd.yggdrasil.mia.cx`     |
| qBittorrent   | `https://qbittorrent.yggdrasil.mia.cx` |
| Tdarr         | `https://tdarr.yggdrasil.mia.cx`       |
| OpenSpeedTest | `https://speedtest.mia.cx`             |

## NFS Exports

| Export    | Server   | Path             | Contents                          |
| --------- | -------- | ---------------- | --------------------------------- |
| Media     | 10.0.1.2 | `/mnt/media`     | MergerFS media library (~29Ti)    |
| Critical  | 10.0.1.2 | `/mnt/nvme`      | Databases, configs, critical data |
| Downloads | 10.0.1.8 | `/mnt/downloads` | Download staging                  |

## Namespaces

| Namespace         | Services                                                                                                             |
| ----------------- | -------------------------------------------------------------------------------------------------------------------- |
| `kube-system`     | Traefik, kube-vip, CoreDNS, cert-manager                                                                             |
| `argocd`          | ArgoCD server + repo server                                                                                          |
| `longhorn-system` | Longhorn storage                                                                                                     |
| `authentik`       | Authentik server + worker + PostgreSQL + Redis                                                                       |
| `media`           | Jellyfin, Sonarr, Radarr, Lidarr, Readarr, Prowlarr, SABnzbd, qBittorrent, FlareSolverr, Privoxy, Prefetcharr, Tdarr |
| `nextcloud`       | Nextcloud + MariaDB + Redis                                                                                          |
| `immich`          | Immich server + ML + PostgreSQL + Valkey                                                                             |
| `vaultwarden`     | Vaultwarden                                                                                                          |
| `netbird`         | Exit node DaemonSet                                                                                                  |
| `pelican`         | Pelican Panel                                                                                                        |
| `speedtest`       | OpenSpeedTest                                                                                                        |
