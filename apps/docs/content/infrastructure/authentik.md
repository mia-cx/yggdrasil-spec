---
title: Authentik LXC
---

# Authentik LXC

Identity provider for SSO across all services, deployed in a dedicated LXC independent of K3s.

## Overview

| Property | Value |
|----------|-------|
| IP | 10.0.1.3 |
| VMID | 1003 |
| Template | debian-12-standard |
| vCPUs | 2 |
| RAM | 1-2GB |
| Disk | 10GB |
| Domain | auth.yggdrasil.mia.cx |

## Why LXC?

- **Resilience:** Stays up even if K3s is down
- **Recovery:** Can authenticate to fix K3s issues
- **Independence:** Backup/restore without K3s

## Installation

```bash
apt update && apt install -y docker.io docker-compose
mkdir -p /opt/authentik && cd /opt/authentik

# Download docker-compose.yml from Authentik docs
curl -sL https://goauthentik.io/docker-compose.yml > docker-compose.yml

# Generate secrets
echo "PG_PASS=$(openssl rand -base64 36)" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60)" >> .env
echo "AUTHENTIK_ERROR_REPORTING__ENABLED=false" >> .env

docker-compose up -d
```

## Components

- PostgreSQL (included in compose)
- Redis (included in compose)
- Authentik server
- Authentik worker

## SSO Integration by Service

| Service | Method | Auto-create users? |
|---------|--------|-------------------|
| Netbird | OIDC | Yes |
| Jellyfin | OIDC (plugin) | Yes, with group-based permissions |
| Nextcloud | OIDC | Yes |
| Forgejo | OIDC | Yes |
| Grafana | OIDC | Yes |
| Proxmox | OIDC (plugin) | Manual |
| Sonarr/Radarr | Proxy auth | N/A (protected, not user-aware) |

## Creating OIDC Applications

For each service:

1. Admin → Applications → Create
2. Provider: OAuth2/OpenID Provider
3. Set redirect URIs per service docs
4. Copy Client ID + Secret

## Groups

Create groups for access control:

| Group | Purpose |
|-------|---------|
| media-users | Jellyfin read access |
| media-admin | Jellyfin admin access |
| netbird-users | Netbird network access |
| admin | Full admin access |

## Backup

```bash
# Backup PostgreSQL
docker exec authentik-postgresql pg_dump -U authentik authentik > backup.sql

# Backup media/config
tar -czf authentik-media.tar.gz /opt/authentik/media
```
