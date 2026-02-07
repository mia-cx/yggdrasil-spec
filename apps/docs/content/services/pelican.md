---
title: Pelican
---

# Pelican

## Overview

| Property  | Value                                              |
| --------- | -------------------------------------------------- |
| Image     | Pelican Panel (see chart)                          |
| Port      | 80                                                 |
| Namespace | `pelican`                                          |
| URL       | `https://pelican.yggdrasil.mia.cx`                 |
| Storage   | Longhorn (panel/db), local disk (Wings game files) |

Game server management platform (Pterodactyl fork). Split architecture: the Panel runs in K3s, while Wings runs in a dedicated VM to isolate resource-hungry game containers.

## Architecture

| Component | Location                | Purpose                                  |
| --------- | ----------------------- | ---------------------------------------- |
| **Panel** | K3s                     | Web UI, API, database                    |
| **Wings** | Dedicated VM (10.0.1.6) | Docker daemon for game server containers |

```
┌─────────────────────────────────────┐
│ K3s (10.0.1.3)                      │
│  └── Pelican Panel                  │
│       ├── Web UI                    │
│       ├── API                       │
│       └── MySQL/MariaDB             │
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

| File                               | Purpose              |
| ---------------------------------- | -------------------- |
| `argocd/pelican/ingressroute.yaml` | Traefik IngressRoute |

## Deployment

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

### Panel (K3s)

Deploy Panel with MariaDB/MySQL, Redis, and persistent storage for `/app/var/`:

```bash
kubectl apply -f argocd/pelican/ingressroute.yaml
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

| Component   | Storage              | Rationale                       |
| ----------- | -------------------- | ------------------------------- |
| Panel (K3s) | Longhorn             | Database and app config         |
| Wings (VM)  | Local disk           | Best performance for game files |
| Wings (VM)  | NFS mount (optional) | For shared/backed-up data       |
