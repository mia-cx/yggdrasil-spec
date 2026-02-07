---
title: Media Stack
---

# Media Stack

## Overview

| Property  | Value                                     |
| --------- | ----------------------------------------- |
| Namespace | `media`                                   |
| Chart     | `bjw-s/app-template` (v3)                 |
| Storage   | Longhorn (config), NFS (media, downloads) |

Automated media acquisition, organization, and transcoding. All ten services run in the `media` namespace and share NFS volumes for media and downloads.

| Service      | Image                               | Port | Purpose                 |
| ------------ | ----------------------------------- | ---- | ----------------------- |
| Sonarr       | `lscr.io/linuxserver/sonarr`        | 8989 | TV show automation      |
| Radarr       | `lscr.io/linuxserver/radarr`        | 7878 | Movie automation        |
| Lidarr       | `lscr.io/linuxserver/lidarr`        | 8686 | Music automation        |
| Prowlarr     | `lscr.io/linuxserver/prowlarr`      | 9696 | Indexer management      |
| SABnzbd      | `lscr.io/linuxserver/sabnzbd`       | 8080 | Usenet downloader       |
| qBittorrent  | `lscr.io/linuxserver/qbittorrent`   | 8080 | Torrent client          |
| FlareSolverr | `ghcr.io/flaresolverr/flaresolverr` | 8191 | Cloudflare bypass proxy |
| Privoxy      | `docker.io/vimagick/privoxy`        | 8118 | HTTP proxy              |
| Prefetcharr  | `docker.io/phueber/prefetcharr`     | --   | Prefetch next seasons   |
| Tdarr        | `docker.io/haveagitgat/tdarr`       | 8265 | Transcode automation    |

## Architecture

```
                   ┌─────────────┐
                   │  Prowlarr   │ Indexer management
                   │  :9696      │
                   └──────┬──────┘
                          │ pushes indexers to
              ┌───────────┼───────────┐
              ▼           ▼           ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │  Sonarr  │ │  Radarr  │ │  Lidarr  │
        │  :8989   │ │  :7878   │ │  :8686   │
        │  TV      │ │  Movies  │ │  Music   │
        └────┬─────┘ └────┬─────┘ └────┬─────┘
             │             │             │
             ▼             ▼             ▼
        ┌──────────────────────────────────────┐
        │       Download Clients               │
        │  SABnzbd :8080    qBittorrent :8080  │
        │  (Usenet)         (Torrents)         │
        │                   ↕ Privoxy :8118    │
        └──────────┬───────────────────────────┘
                   │ completed downloads
                   ▼
        ┌──────────────────┐    ┌──────────────┐
        │  /media (NFS)    │───▶│  Jellyfin    │
        │  MergerFS 29Ti   │    │  :8096       │
        └──────────────────┘    └──────┬───────┘
                   │                   │ watching activity
                   ▼                   ▼
        ┌──────────────────┐    ┌──────────────┐
        │  Tdarr           │    │  Prefetcharr │
        │  :8265           │    │  (daemon)    │
        │  Transcode       │    │  Prefetch    │
        └──────────────────┘    └──────────────┘

        ┌──────────────────┐
        │  FlareSolverr    │ Cloudflare bypass for Prowlarr
        │  :8191           │
        └──────────────────┘
```

## Manifests

| Directory              | Files                              |
| ---------------------- | ---------------------------------- |
| `argocd/sonarr/`       | `values.yaml`, `ingressroute.yaml` |
| `argocd/radarr/`       | `values.yaml`, `ingressroute.yaml` |
| `argocd/lidarr/`       | `values.yaml`, `ingressroute.yaml` |
| `argocd/prowlarr/`     | `values.yaml`, `ingressroute.yaml` |
| `argocd/sabnzbd/`      | `values.yaml`, `ingressroute.yaml` |
| `argocd/qbittorrent/`  | `values.yaml`, `ingressroute.yaml` |
| `argocd/flaresolverr/` | `values.yaml`                      |
| `argocd/privoxy/`      | `values.yaml`                      |
| `argocd/prefetcharr/`  | `values.yaml`                      |
| `argocd/tdarr/`        | `values.yaml`, `ingressroute.yaml` |

## Deployment

### Prerequisites

Ensure shared NFS PVCs exist:

```bash
kubectl apply -f argocd/jellyfin/storage.yaml
```

### Via ArgoCD (recommended)

Push to `main` and ArgoCD syncs automatically. Or apply manually:

```bash
kubectl apply -f argocd/_apps/sonarr.yaml
kubectl apply -f argocd/_apps/radarr.yaml
kubectl apply -f argocd/_apps/lidarr.yaml
kubectl apply -f argocd/_apps/prowlarr.yaml
kubectl apply -f argocd/_apps/sabnzbd.yaml
kubectl apply -f argocd/_apps/qbittorrent.yaml
kubectl apply -f argocd/_apps/flaresolverr.yaml
kubectl apply -f argocd/_apps/privoxy.yaml
kubectl apply -f argocd/_apps/prefetcharr.yaml
kubectl apply -f argocd/_apps/tdarr.yaml
```

### Via Helm (manual)

```bash
helm repo add bjw-s https://bjw-s-labs.github.io/helm-charts
helm repo update

for svc in sonarr radarr lidarr prowlarr sabnzbd qbittorrent flaresolverr privoxy prefetcharr tdarr; do
  helm install $svc bjw-s/app-template --namespace media -f argocd/$svc/values.yaml
done
```

## Configuration

### Prowlarr -- Indexers

1. Open Prowlarr, add your indexers
2. Under Settings → Apps, add Sonarr, Radarr, and Lidarr
3. Set FlareSolverr proxy: `http://flaresolverr.media:8191`

### Sonarr / Radarr / Lidarr -- Download Clients

In each \*arr app, add download clients under Settings → Download Clients:

| Client      | Host                | Port |
| ----------- | ------------------- | ---- |
| SABnzbd     | `sabnzbd.media`     | 8080 |
| qBittorrent | `qbittorrent.media` | 8080 |

### qBittorrent -- Privoxy

In qBittorrent WebUI → Settings → Connection → Proxy:

- Type: HTTP
- Host: `privoxy.media`
- Port: `8118`

### Prefetcharr -- API Keys

Create a Kubernetes secret with Sonarr and Jellyfin API keys, then reference them in `values.yaml` via `envFrom`.

### Path Mappings

Configure root folders in each \*arr app:

| App    | Root Folder     |
| ------ | --------------- |
| Sonarr | `/media/tv`     |
| Radarr | `/media/movies` |
| Lidarr | `/media/music`  |

Download path: `/downloads` (shared across all apps and download clients).

## Access

All services use the `internal-only` middleware -- accessible only via LAN or Netbird overlay.

| Service     | URL                                    |
| ----------- | -------------------------------------- |
| Sonarr      | `https://sonarr.yggdrasil.mia.cx`      |
| Radarr      | `https://radarr.yggdrasil.mia.cx`      |
| Lidarr      | `https://lidarr.yggdrasil.mia.cx`      |
| Prowlarr    | `https://prowlarr.yggdrasil.mia.cx`    |
| SABnzbd     | `https://sabnzbd.yggdrasil.mia.cx`     |
| qBittorrent | `https://qbittorrent.yggdrasil.mia.cx` |
| Tdarr       | `https://tdarr.yggdrasil.mia.cx`       |

FlareSolverr, Privoxy, and Prefetcharr are internal-only services with no web UI exposed via ingress.

## Storage

All services share NFS volumes via PVCs defined in `argocd/jellyfin/storage.yaml`:

| PVC                 | Mount        | Source                        |
| ------------------- | ------------ | ----------------------------- |
| `media-nfs-pvc`     | `/media`     | MergerFS media library (29Ti) |
| `downloads-nfs-pvc` | `/downloads` | Download staging (old server) |
| `nvme-nfs-pvc`      | `/nvme`      | Critical data (NVMe)          |

Each service also gets a Longhorn PVC for `/config` (app database, settings).
