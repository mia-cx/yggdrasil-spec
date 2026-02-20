---
title: Pelican
---

# Pelican

## Overview

| Property  | Value                                              |
| --------- | -------------------------------------------------- |
| Image     | ghcr.io/pelican-dev/panel                          |
| Port      | 80                                                 |
| Namespace | `pelican`                                          |
| URL       | `https://panel.yggdrasil.mia.cx`                  |
| Storage   | Longhorn (panel/db), local disk (Wings game files) |

Game server management platform (Pterodactyl fork). Split architecture: the Panel runs in K3s, while Wings runs in a dedicated VM to isolate resource-hungry game containers.

## Architecture

| Component | Location                | Purpose                                  |
| --------- | ----------------------- | ---------------------------------------- |
| **Panel** | K3s                     | Web UI, API                              |
| **PostgreSQL** | K3s (pelican ns)    | Database (CloudNativePG)               |
| **Valkey** | K3s (pelican ns)        | Sessions, cache (Redis-compatible, official chart) |
| **Wings** | Dedicated VM (10.0.1.6) | Docker daemon for game server containers |

```
┌─────────────────────────────────────┐
│ K3s (10.0.1.3)                      │
│  └── Pelican Panel                  │
│       ├── Web UI                    │
│       ├── API                       │
│       ├── PostgreSQL (pelican-database)   │
│       └── Valkey (pelican-valkey)   │
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

| File                               | Purpose                                  |
| ---------------------------------- | ---------------------------------------- |
| `argocd/_apps/pelican.yaml`         | ArgoCD Application (bjw-s/app-template) |
| `argocd/pelican/postgresql.yaml`       | CloudNativePG Cluster for Panel       |
| `argocd/_apps/pelican-valkey.yaml`  | Valkey for sessions/cache (official)    |
| `argocd/pelican/values.yaml`        | Helm values overrides                    |
| `argocd/pelican/ingressroute.yaml`  | Traefik IngressRoute                     |

## Deployment

### Panel (K3s)

Deployed via ArgoCD; no manual `kubectl apply` needed. Uses bjw-s/app-template Helm chart (same as Jellyfin, Radarr, etc.). After first sync:

1. Visit `https://panel.yggdrasil.mia.cx/installer` to run the installer.
2. **Back up your APP_KEY** (generated on first start):
   ```bash
   kubectl logs -n pelican deployment/pelican-panel | grep 'Generated app key:'
   ```
3. Database (PostgreSQL) and Valkey (Redis-compatible) are pre-configured; complete the installer (admin account, panel name).

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

| Component       | Storage              | Rationale                       |
| --------------- | -------------------- | ------------------------------- |
| Panel (K3s)     | Longhorn             | App config, logs               |
| PostgreSQL (K3s) | Longhorn           | Database                        |
| Valkey (K3s)    | Longhorn             | Sessions, cache                 |
| Wings (VM)      | Local disk           | Best performance for game files |
| Wings (VM)      | NFS mount (optional) | For shared/backed-up data       |
