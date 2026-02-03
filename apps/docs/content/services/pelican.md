---
title: Pelican (Game Servers)
---

# Pelican (Game Servers)

Pelican (Pterodactyl fork) for managing game servers.

## Architecture

Pelican has two components:

| Component | Location | Purpose |
|-----------|----------|---------|
| **Panel** | K3s | Web UI, API, database |
| **Wings** | Dedicated VM | Docker daemon for game server containers |

```
┌─────────────────────────────────────┐
│ K3s (10.0.1.4)                      │
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

## Why Separate VM for Wings?

- Wings requires Docker socket access (`/var/run/docker.sock`)
- Creates/manages its own containers (game servers)
- LXC is unsupported and unreliable (nested container issues)
- Game servers are resource-hungry and bursty
- Isolation prevents game servers from affecting other services

## Wings VM Setup

### VM Specs

| Property | Value |
|----------|-------|
| IP | 10.0.1.6 |
| VMID | 1006 |
| vCPUs | 4-8 (scale as needed) |
| RAM | 4-8GB base (scale as needed) |
| Disk | 50-100GB (game files) |
| OS | Ubuntu 22.04 or Debian 12 |

### Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

### Install Wings

```bash
# Create directory
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

## Panel in K3s

The Panel (web UI + database) runs in K3s like any other service.

### Helm/Manifest

Deploy Panel with:
- MariaDB or MySQL for database
- Redis for caching/queues
- Persistent storage for `/app/var/`

### IngressRoute

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: pelican
  namespace: pelican
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`panel.yggdrasil.mia.cx`)
      kind: Rule
      services:
        - name: pelican-panel
          port: 80
  tls:
    secretName: wildcard-tls
```

## Network Ports

Game servers need various ports exposed. Configure your router to forward game-specific ports to the Wings VM (10.0.1.4).

Common ports:
- Minecraft: 25565 (TCP/UDP)
- Valheim: 2456-2458 (UDP)
- ARK: 7777, 27015 (UDP)

## Storage

Game server files can be stored on:
- Local disk (fastest)
- NFS mount from Storage LXC (shared, backed up)

For large game files, local storage on the Wings VM is usually better for performance.
