---
title: Pelican
---

# Pelican

## Migration planning

The [accepted K3s integration](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743564646) preserves the Panel and Wings browser names. Existing access stays in place until NetBird passes its stability pilot and Mia approves this service's cutover.

| Connection                 | Planned private path                                                                                     |
| -------------------------- | -------------------------------------------------------------------------------------------------------- |
| Browser to Panel           | Private Traefik to the Panel Service.                                                                    |
| Panel and browser to Wings | Existing Wings HTTPS/WebSocket name through private Traefik, then NetworkEgress to the Wings peer's API. |
| Wings to Panel             | Private Panel URL and native authenticated daemon API.                                                   |
| Game operator to SFTP      | Separate NetBird-only SFTP alias directly to Wings on its configured port.                               |

Wings is not exclusively server-to-server traffic: browser consoles and signed file transfers also reach it. Preserve native node/JWT permissions and avoid interactive login redirects on machine or signed-token endpoints. Public game allocations remain separate.

Use Pelican's `daemon_sftp_alias` for the separate SFTP hostname; it does not include the port. Reject public and direct LAN SFTP access at the approved cutover, not during foundation setup. The [connection contract](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743163099) and [SFTP decision](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743232272) retain the evidence and inventory checks.

The deployment information below describes the existing arrangement, not completed migration work.

## Overview

| Property  | Value                                              |
| --------- | -------------------------------------------------- |
| Image     | ghcr.io/pelican-dev/panel                          |
| Port      | 80                                                 |
| Namespace | `pelican`                                          |
| URL       | `https://panel.mia.cx`                             |
| Storage   | Longhorn (panel/db), local disk (Wings game files) |

Game server management platform (Pterodactyl fork). Split architecture: the Panel runs in K3s, while Wings runs in a dedicated VM to isolate resource-hungry game containers.

## Architecture

| Component        | Location                | Purpose                                            |
| ---------------- | ----------------------- | -------------------------------------------------- |
| **Panel**        | K3s                     | Web UI, API                                        |
| **PostgreSQL**   | K3s (pelican ns)        | Database (CloudNativePG)                           |
| **Valkey**       | K3s (pelican ns)        | Sessions, cache (Redis-compatible, official chart) |
| **Scheduler**    | K3s (CronJob)           | Laravel schedule:run (every minute)                |
| **Queue worker** | K3s (Deployment)        | Background jobs (backups, power actions)           |
| **Wings**        | Dedicated VM (10.0.1.6) | Docker daemon for game server containers           |

```
┌─────────────────────────────────────┐
│ K3s (10.0.1.3)                      │
│  └── Pelican Panel                  │
│       ├── Web UI                    │
│       ├── API                       │
│       ├── PostgreSQL (pelican-database)   │
│       ├── Valkey (pelican-valkey)   │
│       ├── Scheduler (CronJob)      │
│       └── Queue worker (Deployment) │
└─────────────────────────────────────┘
              │
              │ API calls
              ▼
┌─────────────────────────────────────┐
│ Wings VM (10.0.1.6, VMID 1006)      │
│  ├── Docker                         │
│  └── Wings daemon                   │
│       ├── Minecraft server          │
│       ├── Valheim server            │
│       └── ...game containers        │
└─────────────────────────────────────┘
```

**Why a separate VM for Wings?**

- Wings requires Docker socket access (`/var/run/docker.sock`)
- Creates/manages its own containers (game servers)
- LXC is unsupported (nested container issues)
- Game servers are resource-hungry and bursty
- Isolation prevents game servers from affecting other services

## Manifests

| File                                          | Purpose                                       |
| --------------------------------------------- | --------------------------------------------- |
| `argocd/_apps/pelican.yaml`                   | ArgoCD Application (bjw-s/app-template)       |
| `argocd/pelican/postgresql.yaml`              | CloudNativePG Cluster for Panel               |
| `argocd/_apps/pelican-valkey.yaml`            | Valkey for sessions/cache (official)          |
| `argocd/pelican/values.yaml`                  | Helm values overrides                         |
| `argocd/pelican/ingressroute.yaml`            | Traefik IngressRoute                          |
| `argocd/pelican/scheduler-cronjob.yaml`       | Laravel scheduler (runs every minute)         |
| `argocd/pelican/queue-worker-deployment.yaml` | Laravel queue worker (backups, power actions) |

## Deployment

### Panel (K3s)

Deployed via ArgoCD; no manual `kubectl apply` needed. Uses bjw-s/app-template Helm chart (same as Jellyfin, Radarr, etc.). After first sync:

1. Visit `https://panel.mia.cx/installer` to run the installer.
2. **Back up your APP_KEY** (generated on first start):
   ```bash
   kubectl logs -n pelican deployment/pelican | grep 'Generated app key:'
   ```
3. Database (PostgreSQL) and Valkey (Redis-compatible) are pre-configured; complete the installer (admin account, panel name).
4. **Create scheduler secret** (required for CronJob; in-container crontab does not work):
   ```bash
   APP_KEY=$(kubectl exec -n pelican deployment/pelican -- cat /var/www/html/.env 2>/dev/null | grep '^APP_KEY=' | cut -d= -f2-)
   kubectl create secret generic pelican-scheduler-secrets -n pelican --from-literal=APP_KEY="$APP_KEY" --dry-run=client -o yaml | kubectl apply -f -
   ```

### Wings VM

| Property | Value                        |
| -------- | ---------------------------- |
| IP       | 10.0.1.6                     |
| VMID     | 1006                         |
| vCPUs    | 4-8 (scale as needed)        |
| RAM      | 4-8GB base (scale as needed) |
| Disk     | 50-100GB (game files)        |
| OS       | Ubuntu 22.04 or Debian 12    |

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Create Wings directory
sudo mkdir -p /etc/pterodactyl
cd /etc/pterodactyl

# Download Wings
curl -L -o /usr/local/bin/wings \
  "https://github.com/pelican-dev/wings/releases/latest/download/wings_linux_amd64"
chmod u+x /usr/local/bin/wings

# Configure via Panel UI, then start
sudo wings --debug  # test
sudo systemctl enable --now wings  # production
```

## Configuration

### Network Ports

Game servers need various ports exposed. Configure your router to forward game-specific ports to the Wings VM (10.0.1.6).

| Game      | Ports             |
| --------- | ----------------- |
| Minecraft | 25565 (TCP/UDP)   |
| Valheim   | 2456-2458 (UDP)   |
| ARK       | 7777, 27015 (UDP) |

## Storage

| Component        | Storage              | Rationale                       |
| ---------------- | -------------------- | ------------------------------- |
| Panel (K3s)      | Longhorn             | App config, logs                |
| PostgreSQL (K3s) | Longhorn             | Database                        |
| Valkey (K3s)     | Longhorn             | Sessions, cache                 |
| Wings (VM)       | Local disk           | Best performance for game files |
| Wings (VM)       | NFS mount (optional) | For shared/backed-up data       |
