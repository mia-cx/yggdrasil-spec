---
title: Authentik
---

# Authentik

## Overview

| Property  | Value                                        |
| --------- | -------------------------------------------- |
| Type      | K8s (Helm chart)                             |
| Image     | `ghcr.io/goauthentik/server` (chart default) |
| Port      | 9000                                         |
| Namespace | `authentik`                                  |
| Chart     | `authentik/authentik`                        |
| URL       | `https://id.mia.cx`                          |
| Storage   | Longhorn (PostgreSQL, Redis)                 |

Identity provider (IdP) for SSO across all services. Deploys via Helm into Kubernetes with bundled PostgreSQL and Redis.

> **Legacy note:** Authentik was originally deployed in a standalone LXC (10.0.1.3, VMID 1003) using Docker Compose for resilience during K3s bootstrapping. The K8s deployment is now the primary target. The LXC approach is documented below for reference only.

## Prerequisites

```bash
kubectl create namespace authentik
```

Generate secrets:

```bash
export AUTHENTIK_SECRET_KEY=$(openssl rand -base64 36)
export PG_PASS=$(openssl rand -base64 24)

kubectl create secret generic authentik-secrets -n authentik \
  --from-literal=secret-key="$AUTHENTIK_SECRET_KEY" \
  --from-literal=postgresql-password="$PG_PASS"
```

## Setup

### Helm Installation

```bash
helm repo add authentik https://charts.goauthentik.io
helm repo update

helm install authentik authentik/authentik \
  -n authentik \
  -f argocd/authentik/values.yaml
```

### Verify

```bash
kubectl get pods -n authentik -w
```

Wait for all pods to reach `Running`:

- `authentik-server-*`
- `authentik-worker-*`
- `authentik-postgresql-*`
- `authentik-redis-master-*`

### IngressRoute

```bash
kubectl apply -f argocd/authentik/ingressroute.yaml
```

## Configuration

### Invitations

See [Hecate invitations](authentik-invitations.md) for the prepared email invitation
flow with account creation and a choice of TOTP or passkey enrollment.

### Initial Setup

Retrieve the bootstrap password:

```bash
kubectl logs -n authentik \
  -l app.kubernetes.io/name=authentik,app.kubernetes.io/component=server \
  | grep -i "initial"
```

Or set one explicitly in `values.yaml` before install:

```yaml
authentik:
  bootstrap:
    password: "your-initial-password"
    email: "admin@mia.cx"
```

Access the admin UI at `https://id.mia.cx/if/flow/initial-setup/`.

### Embedded Outpost (Forward Auth)

Required for Traefik forward-auth:

1. **Applications** → **Outposts** → edit `authentik Embedded Outpost`
2. Ensure the outpost has the **Proxy** integration enabled
3. Confirm the embedded outpost is available at `ak-outpost-authentik-embedded-outpost.authentik:9000` inside the cluster

### Forward-Auth Provider

For the shared Traefik middleware used by internal services:

1. **Applications** → **Providers** → **Create**
2. Type: **Proxy Provider**
3. Name: `traefik-forward-auth`
4. Authorization flow: `default-provider-authorization-implicit-consent`
5. Mode: **Forward auth (domain level)**
6. External host: `https://id.mia.cx`
7. Internal host: leave empty unless you have a specific backend override need
8. Assign the provider to the embedded outpost

This repo is using the domain-level model so one Authentik forward-auth provider can protect multiple Traefik routes.

### Groups

| Group           | Purpose                     |
| --------------- | --------------------------- |
| `admins`        | Full access to all services |
| `users`         | Standard user access        |
| `media-users`   | Jellyfin / media access     |
| `media-admin`   | Jellyfin admin              |
| `netbird-users` | Netbird network access      |

### Creating OIDC Applications

For each service:

1. Admin → Applications → Create
2. Provider: OAuth2/OpenID Provider
3. Set redirect URIs per service docs
4. Copy Client ID + Secret

### SSO Integration by Service

| Service       | Method        | Auto-create users?                |
| ------------- | ------------- | --------------------------------- |
| Netbird       | OIDC          | Yes                               |
| Jellyfin      | OIDC (plugin) | Yes, with group-based permissions |
| Nextcloud     | OIDC          | Yes                               |
| Forgejo       | OIDC          | Yes                               |
| Grafana       | OIDC          | Yes                               |
| Proxmox       | OIDC (plugin) | Manual                            |
| Sonarr/Radarr | Proxy auth    | N/A (protected, not user-aware)   |

### DNS Records

| Record                | Type | Value                            |
| --------------------- | ---- | -------------------------------- |
| `id.mia.cx`           | A    | `<public-ip>` or CNAME to tunnel |
| `id.yggdrasil.mia.cx` | A    | `10.0.128.1` (VIP)               |

## Upgrade

```bash
helm repo update
helm upgrade authentik authentik/authentik \
  -n authentik \
  -f argocd/authentik/values.yaml
```

## Backup

```bash
kubectl exec -n authentik authentik-postgresql-0 -- \
  pg_dump -U authentik authentik > authentik-backup.sql
```

## Verification

```bash
kubectl get pods -n authentik
kubectl get ingressroute -n authentik
```

## Troubleshooting

### Check Logs

```bash
kubectl logs -n authentik -l app.kubernetes.io/component=server -f
kubectl logs -n authentik -l app.kubernetes.io/component=worker -f
```

### Reset Admin Password

```bash
kubectl exec -it -n authentik deployment/authentik-server -- \
  ak create_recovery_key 10 akadmin
```

Outputs a recovery link valid for 10 minutes.

### Database Connection Issues

```bash
kubectl exec -it -n authentik authentik-postgresql-0 -- \
  psql -U authentik -d authentik -c "SELECT 1"
```

---

## Legacy: LXC Deployment

> This section documents the original Docker Compose deployment in a dedicated LXC. It remains useful during K3s bootstrapping or disaster recovery.

| Property | Value              |
| -------- | ------------------ |
| IP       | 10.0.1.3           |
| VMID     | 1003               |
| Template | debian-12-standard |
| vCPUs    | 2                  |
| RAM      | 1-2GB              |
| Disk     | 10GB               |

**Why LXC?** Authentik stays available even if K3s is completely down, allowing you to authenticate and fix cluster issues.

```bash
apt update && apt install -y docker.io docker-compose
mkdir -p /opt/authentik && cd /opt/authentik

curl -sL https://goauthentik.io/docker-compose.yml > docker-compose.yml

echo "PG_PASS=$(openssl rand -base64 36)" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60)" >> .env
echo "AUTHENTIK_ERROR_REPORTING__ENABLED=false" >> .env

docker-compose up -d
```

Backup:

```bash
docker exec authentik-postgresql pg_dump -U authentik authentik > backup.sql
tar -czf authentik-media.tar.gz /opt/authentik/media
```
