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

Automated media acquisition, organization, and transcoding. All services run in the `media` namespace; most share NFS volumes for media and downloads. Seerr uses only Longhorn (config).

| Service      | Image                               | Port | Purpose                        |
| ------------ | ----------------------------------- | ---- | ------------------------------ |
| Seerr        | `ghcr.io/seerr-team/seerr`          | 5055 | Request/discovery (Jellyfin)    |
| Sonarr       | `lscr.io/linuxserver/sonarr`        | 8989 | TV show automation             |
| Radarr       | `lscr.io/linuxserver/radarr`        | 7878 | Movie automation               |
| Lidarr       | `lscr.io/linuxserver/lidarr`        | 8686 | Music automation               |
| Readarr      | `docker.io/linuxserver/readarr:develop-0.4.18.2805-ls157` | 8787 | Ebook/audiobook automation    |
| rreading-glasses | `docker.io/blampe/rreading-glasses:latest` | 8788 | Readarr metadata API (Goodreads) |
| Prowlarr     | `lscr.io/linuxserver/prowlarr`      | 9696 | Indexer management             |
| SABnzbd      | `lscr.io/linuxserver/sabnzbd`       | 8080 | Usenet downloader              |
| qBittorrent  | `lscr.io/linuxserver/qbittorrent`   | 8080 | Torrent client                 |
| FlareSolverr | `ghcr.io/flaresolverr/flaresolverr` | 8191 | Cloudflare bypass proxy        |
| Privoxy      | `docker.io/vimagick/privoxy`        | 8118 | HTTP proxy                     |
| Prefetcharr  | `docker.io/phueber/prefetcharr`     | --   | Prefetch next seasons          |
| Jellyfin-Auto-Collections | `ghcr.io/ghomashudson/jellyfin-auto-collections` | -- | Sync collections (IMDb, Letterboxd, etc.) |
| Tdarr        | `docker.io/haveagitgat/tdarr`       | 8265 | Transcode automation           |
| Tunarr       | `docker.io/chrisbenincasa/tunarr`   | 8000 | IPTV from Jellyfin/Plex        |

## Architecture

```
        ┌──────────────────┐
        │  Seerr :5055     │ Request/discovery UI → Jellyfin + Sonarr/Radarr
        └────────┬─────────┘
                 │
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
                   │                   │ watching activity / collections API
                   ▼                   ▼
        ┌──────────────────┐    ┌──────────────┐     ┌──────────────────────────────┐
        │  Tdarr           │    │  Prefetcharr │     │  Jellyfin-Auto-Collections   │
        │  :8265           │    │  (daemon)    │     │  (cron) IMDb/Letterboxd sync  │
        │  Transcode       │    │  Prefetch    │     └──────────────────────────────┘
        └──────────────────┘    └──────────────┘

        ┌──────────────────┐
        │  FlareSolverr    │ Cloudflare bypass for Prowlarr
        │  :8191           │
        └──────────────────┘
```

## Manifests

| Directory              | Files                              |
| ---------------------- | ---------------------------------- |
| `argocd/seerr/`        | `values.yaml`, `ingressroute.yaml` |
| `argocd/sonarr/`       | `values.yaml`, `ingressroute.yaml` |
| `argocd/radarr/`       | `values.yaml`, `ingressroute.yaml` |
| `argocd/lidarr/`       | `values.yaml`, `ingressroute.yaml` |
| `argocd/readarr/`      | `values.yaml`, `pvc.yaml`, `ingressroute.yaml` |
| `argocd/rreading-glasses/` | `postgresql.yaml` (CNPG), `deployment.yaml` |
| `argocd/prowlarr/`     | `values.yaml`, `ingressroute.yaml` |
| `argocd/sabnzbd/`      | `values.yaml`, `ingressroute.yaml` |
| `argocd/qbittorrent/`  | `values.yaml`, `ingressroute.yaml` |
| `argocd/flaresolverr/` | `values.yaml`                      |
| `argocd/privoxy/`      | `values.yaml`                      |
| `argocd/prefetcharr/`  | `values.yaml`, `configmap.yaml`    |
| `argocd/jellyfin-auto-collections/` | `cronjob.yaml`, `configmap.yaml`, `README.md` |
| `argocd/tdarr/`        | `values.yaml`, `ingressroute.yaml` |
| `argocd/tunarr/`       | `values.yaml`, `pvc.yaml`, `ingressroute.yaml` |

## Deployment

### Prerequisites

Ensure shared NFS PVCs exist:

```bash
kubectl apply -f argocd/jellyfin/storage.yaml
```

### Via ArgoCD (recommended)

Push to `main` and ArgoCD syncs automatically. Or apply manually:

```bash
kubectl apply -f argocd/_apps/seerr.yaml
kubectl apply -f argocd/_apps/sonarr.yaml
kubectl apply -f argocd/_apps/radarr.yaml
kubectl apply -f argocd/_apps/lidarr.yaml
kubectl apply -f argocd/_apps/readarr.yaml
kubectl apply -f argocd/_apps/rreading-glasses.yaml
kubectl apply -f argocd/_apps/prowlarr.yaml
kubectl apply -f argocd/_apps/sabnzbd.yaml
kubectl apply -f argocd/_apps/qbittorrent.yaml
kubectl apply -f argocd/_apps/flaresolverr.yaml
kubectl apply -f argocd/_apps/privoxy.yaml
kubectl apply -f argocd/_apps/prefetcharr.yaml
kubectl apply -f argocd/_apps/jellyfin-auto-collections.yaml
kubectl apply -f argocd/_apps/tdarr.yaml
kubectl apply -f argocd/_apps/tunarr.yaml
```

### Via Helm (manual)

```bash
helm repo add bjw-s https://bjw-s-labs.github.io/helm-charts
helm repo update

for svc in seerr sonarr radarr lidarr readarr prowlarr sabnzbd qbittorrent flaresolverr privoxy prefetcharr tdarr tunarr; do
  helm install $svc bjw-s/app-template --namespace media -f argocd/$svc/values.yaml
done

for svc in seerr sonarr radarr lidarr readarr prowlarr sabnzbd qbittorrent tdarr tunarr; do
  kubectl apply -f argocd/$svc/ingressroute.yaml
done
```

## Configuration

### Prowlarr -- Indexers

1. Open Prowlarr, add your indexers
2. Under Settings → Apps, add Sonarr, Radarr, Lidarr, and Readarr
3. Set FlareSolverr proxy: `http://flaresolverr.media:8191`

### Sonarr / Radarr / Lidarr / Readarr -- Download Clients

In each \*arr app, add download clients under Settings → Download Clients:

| Client      | Host                | Port |
| ----------- | ------------------- | ---- |
| SABnzbd     | `sabnzbd.media`     | 8080 |
| qBittorrent | `qbittorrent.media` | 8080 |

### Readarr — rreading-glasses metadata (self-hosted)

[rreading-glasses](https://github.com/blampe/rreading-glasses) is a drop-in replacement for Readarr’s retired metadata service (Goodreads). After deploying, point Readarr at it:

1. In Readarr, open **Settings → Development** (this page is hidden; go to `http(s)://readarr.yggdrasil.mia.cx/settings/development`).
2. Set **Metadata Provider Source** to `http://rreading-glasses.media:8788`.
3. Click **Save**.

You can switch back to the public instance (`https://api.bookinfo.pro`) or disable by clearing the field. Requires CloudNative-PG operator (same as Immich/Pelican).

### qBittorrent -- Privoxy

In qBittorrent WebUI → Settings → Connection → Proxy:

- Type: HTTP
- Host: `privoxy.media`
- Port: `8118`

### Prefetcharr — TOML config and API keys

Prefetcharr uses a TOML config ([p-hueber/prefetcharr](https://github.com/p-hueber/prefetcharr)). The static part (interval, log_level, urls, etc.) lives in `argocd/prefetcharr/configmap.yaml`; API keys stay in a Secret.

**1. Create the Secret** (Jellyfin and Sonarr API keys only):

```bash
kubectl create secret generic prefetcharr-secrets -n media \
  --from-literal=JELLYFIN_API_KEY="your-jellyfin-api-key" \
  --from-literal=SONARR_API_KEY="your-sonarr-api-key"
```

Where to find each key:

- **Jellyfin:** Dashboard → Administration → API Keys → create one named `prefetcharr`
- **Sonarr:** Settings → General → API Key

**2. Edit the config** (optional): Change interval, `prefetch_num`, `log_level`, or other options in `argocd/prefetcharr/configmap.yaml`. The init container merges that template with the Secret at startup via `envsubst`.

### Jellyfin-Auto-Collections — API key and user ID

Create a secret with your Jellyfin API key and user ID (see `argocd/jellyfin-auto-collections/README.md`):

```bash
kubectl create secret generic jellyfin-auto-collections-secrets \
  -n media \
  --from-literal=JELLYFIN_API_KEY='your-api-key' \
  --from-literal=JELLYFIN_USER_ID='your-jellyfin-user-uuid'
```

User ID is the UUID from the URL when viewing your user in Jellyfin Dashboard. The CronJob uses in-cluster URL `http://jellyfin.media:8096` by default; override with `JELLYFIN_SERVER_URL` in the secret if needed.

### Jellyfin — Streams or offline downloads dropping after a few minutes

If playback or offline sync stops and requires a restart:

1. **Traefik timeouts** — `argocd/traefik/values.yaml` sets `readTimeout=0` and `writeTimeout=0` for the websecure entrypoint so long-lived streams are not cut.
2. **NFS resilience** — `argocd/k3s/nfs-pvs.yaml` adds `timeo=600`, `retrans=3`, and larger `rsize`/`wsize` for media/nvme PVs. If the PVs already exist, you must recreate them (or migrate) for mountOptions to apply.
3. **Direct access test** — Connect to Jellyfin via `http://jellyfin.media:8096` (in-cluster) or port-forward, bypassing Traefik. If that works, the proxy was the cause.
4. **Jellyfin Dashboard** — Transcoding → Temporary transcoding path: ensure it uses `/cache` (emptyDir, fast local I/O), not NFS.

### Tdarr — Node resources in UI

The Tdarr web UI shows **host (node)** RAM and CPU for each node (e.g. "OS Mem: 7.7GB/31.3GB"), not the container limits. That is expected: the process reads from the OS and in Kubernetes the pod often sees the node’s totals. Actual enforcement is via the pod’s resource limits in `argocd/tdarr/values.yaml` (e.g. 8 Gi memory, 4 CPU per node). Ignore the "available" numbers in the UI for scheduling; the limits are what apply.

### Seerr — Jellyfin and Sonarr/Radarr

In Seerr’s initial setup (or Settings), add:

- **Jellyfin:** URL `http://jellyfin.media:8096` and an API key (Dashboard → Administration → API Keys). Use the in-cluster hostname so Seerr reaches Jellyfin without ingress.
- **Sonarr / Radarr / Lidarr / Readarr:** Under Settings → Services, add each with URL `http://sonarr.media:8989`, `http://radarr.media:7878`, `http://lidarr.media:8686`, `http://readarr.media:8787` and their API keys (Settings → General → API Key in each app).

Seerr uses SQLite by default (stored in `/app/config`). For PostgreSQL, see [Seerr docs](https://docs.seerr.dev).

### Tunarr — Jellyfin server

In Tunarr’s web UI, add your Jellyfin server (URL and API key). Use the in-cluster URL (e.g. `http://jellyfin.media:8096`) so Tunarr can reach Jellyfin without going through ingress. Create an API key in Jellyfin (Dashboard → API Keys) for Tunarr. Tunarr exposes an HDHR tuner and M3U for Plex/Jellyfin/Emby or IPTV apps (e.g. Tivimate, UHF).

### Path Mappings

Configure root folders in each \*arr app:

| App     | Root Folder      |
| ------- | ---------------- |
| Sonarr  | `/media/tv`      |
| Radarr  | `/media/movies`  |
| Lidarr  | `/media/music`   |
| Readarr | `/media/books`   |

Download path: `/downloads` (shared across all apps and download clients).

## Access

All services use the `internal-only` middleware -- accessible only via LAN or Netbird overlay.

| Service     | URL                                    |
| ----------- | -------------------------------------- |
| Seerr       | `https://seerr.yggdrasil.mia.cx`       |
| Sonarr      | `https://sonarr.yggdrasil.mia.cx`      |
| Radarr      | `https://radarr.yggdrasil.mia.cx`      |
| Lidarr      | `https://lidarr.yggdrasil.mia.cx`      |
| Readarr     | `https://readarr.yggdrasil.mia.cx`     |
| Prowlarr    | `https://prowlarr.yggdrasil.mia.cx`    |
| SABnzbd     | `https://sabnzbd.yggdrasil.mia.cx`     |
| qBittorrent | `https://qbittorrent.yggdrasil.mia.cx` |
| Tdarr       | `https://tdarr.yggdrasil.mia.cx`       |
| Tunarr      | `https://tunarr.yggdrasil.mia.cx`      |

FlareSolverr, Privoxy, and Prefetcharr are internal-only services with no web UI exposed via ingress.

### 403 Forbidden — Traefik vs app

- **Traefik (internal-only):** Rejects when the client IP is not in 10.0.0.0/8 or 100.64.0.0/10 (e.g. you're resolving the hostname via public DNS so traffic goes out and back in; see [DNS — LAN](../infrastructure/dns.md#lan-same-network-no-netbird)).
- **App (e.g. Radarr):** Can return 403 for auth or “external” connection rules. To see who returned 403, enable Traefik access logs (see [Traefik — Verify client IP](../infrastructure/traefik.md#verify-client-ip-access-logs)) and check the log line for that request: if the request reached the backend and the backend status is 403, the app returned it. In Radarr go to **Settings → General → Security**: if “Authentication” is “Required for external addresses”, the app treats the request as external when it doesn’t see a local client IP; ensure Traefik is sending `X-Forwarded-For` (Traefik does this by default; the Radarr IngressRoute uses the `forwarded-proto` middleware so the app gets `X-Forwarded-Proto: https` as well).

## Storage

All services share NFS volumes via PVCs defined in `argocd/jellyfin/storage.yaml`. For Tdarr nodes on other sites (e.g. mini-PCs at Elysium/Arcadia), NFS can be made reachable over Netbird so they can transcode from the same library; see [Storage — NFS over Netbird](../infrastructure/storage.md#nfs-over-netbird-cross-site) for how and caveats (latency, fallbacks).

| PVC                 | Mount        | Source                        |
| ------------------- | ------------ | ----------------------------- |
| `media-nfs-pvc`     | `/media`     | MergerFS media library (29Ti) |
| `downloads-nfs-pvc` | `/downloads` | Download staging (old server) |
| `nvme-nfs-pvc`      | `/nvme`      | Critical data (NVMe)          |

Each service also gets a Longhorn PVC for `/config` (app database, settings).
