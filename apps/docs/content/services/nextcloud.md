---
title: Nextcloud
---

# Nextcloud

## Overview

| Property  | Value                                                      |
| --------- | ---------------------------------------------------------- |
| Image     | `nextcloud/nextcloud:32-apache`                            |
| Port      | 80                                                         |
| Namespace | `nextcloud`                                                |
| Chart     | [`nextcloud/nextcloud`](https://github.com/nextcloud/helm) |
| URL       | `https://cloud.yggdrasil.mia.cx`                           |
| Database  | MariaDB (bundled)                                          |
| Cache     | Redis (bundled)                                            |
| Storage   | Longhorn (app/db), NFS (user files)                        |

Self-hosted file sync, collaboration, and productivity platform. Requires **sequential major version upgrades** -- you cannot skip versions.

## Manifests

| File                                 | Purpose                                     |
| ------------------------------------ | ------------------------------------------- |
| `argocd/nextcloud/values.yaml`       | Helm values for `nextcloud/nextcloud` chart |
| `argocd/nextcloud/storage.yaml`      | Namespace, PV/PVC for Longhorn + NFS        |
| `argocd/nextcloud/ingressroute.yaml` | Traefik IngressRoute + headers middleware   |

## Deployment

```bash
# 1. Create NFS directory for user data
ssh 10.0.1.2 'sudo mkdir -p /mnt/nvme/nextcloud && sudo chmod 777 /mnt/nvme/nextcloud'

# 2. Create longhorn-single StorageClass (if not already present)
kubectl apply -f argocd/k3s/longhorn-single-storageclass.yaml

# 3. Apply namespace + storage
kubectl apply -f argocd/nextcloud/storage.yaml

# 4. Create secrets
kubectl create secret generic nextcloud-secrets \
  --namespace nextcloud \
  --from-literal=nextcloud-username="ncadmin" \
  --from-literal=nextcloud-password="$(openssl rand -base64 16)"

# 5. Add Helm repo & install
helm repo add nextcloud https://nextcloud.github.io/helm/
helm repo update
helm install nextcloud nextcloud/nextcloud \
  --namespace nextcloud \
  -f argocd/nextcloud/values.yaml

# 6. Apply IngressRoute
kubectl apply -f argocd/nextcloud/ingressroute.yaml
```

### Helm Upgrade

```bash
# Back up database first
kubectl exec -n nextcloud nextcloud-mariadb-0 -- \
  mariadb-dump -u nextcloud -p'DB_PASSWORD' nextcloud > nextcloud-db-backup-$(date +%F).sql

# Upgrade (update image.tag in values.yaml, then)
helm upgrade nextcloud nextcloud/nextcloud \
  --namespace nextcloud \
  -f argocd/nextcloud/values.yaml

# Wait for migrations
kubectl rollout status deploy/nextcloud -n nextcloud --timeout=300s

# Verify version
kubectl exec -n nextcloud deploy/nextcloud -- su -s /bin/bash www-data -c "php occ status"
```

If the pod gets stuck in maintenance mode after upgrade:

```bash
kubectl exec -n nextcloud deploy/nextcloud -- su -s /bin/bash www-data -c "php occ upgrade"
kubectl exec -n nextcloud deploy/nextcloud -- su -s /bin/bash www-data -c "php occ maintenance:mode --off"
```

## Configuration

### Real client IP (LAN / public)

Nextcloud should show your real IP (LAN when at home, public when remote), not the Traefik pod IP. That requires:

1. **Traefik** — Preserves and sends the real client IP in `X-Forwarded-For` (see [Traefik](../infrastructure/traefik.md): `service.spec.externalTrafficPolicy: Local` so Traefik sees the real source; `forwardedHeaders.trustedIPs` when a proxy sits in front of Traefik).
2. **Nextcloud** — `trusted_proxies` in `proxy.config.php` must include the IP of the connection Nextcloud receives (the Traefik pod). Values use `10.0.0.0/8` so any in-cluster proxy is trusted regardless of pod CIDR; then `forwarded_for_headers` → `HTTP_X_FORWARDED_FOR` is used as the client IP.

After changing `proxy.config.php` (e.g. in Helm values), redeploy or restart the Nextcloud pod so the config is applied.

### Post-Install

**Get admin password:**

```bash
kubectl get secret nextcloud-secrets -n nextcloud \
  -o jsonpath='{.data.nextcloud-password}' | base64 -d && echo
```

**Verify Redis:** Check Settings → Administration → Overview -- should show no caching warnings.

**occ commands:**

```bash
# Check status
kubectl exec -it -n nextcloud deploy/nextcloud -- su -s /bin/bash www-data -c "php occ status"

# Scan files after migration
kubectl exec -it -n nextcloud deploy/nextcloud -- su -s /bin/bash www-data -c "php occ files:scan --all"

# Add missing indices
kubectl exec -it -n nextcloud deploy/nextcloud -- su -s /bin/bash www-data -c "php occ db:add-missing-indices"
```

### SSO with Authentik

Nextcloud supports OIDC via the `user_oidc` app.

**Authentik provider:**

1. Applications → Providers → Create → OAuth2/OpenID Provider

| Setting            | Value                                                |
| ------------------ | ---------------------------------------------------- |
| Name               | `nextcloud`                                          |
| Authorization flow | `default-provider-authorization-implicit-consent`    |
| Client ID          | `nextcloud`                                          |
| Client Secret      | (copy to K8s secret as `OIDC_CLIENT_SECRET`)         |
| Redirect URIs      | `https://cloud.yggdrasil.mia.cx/apps/user_oidc/code` |
| Signing Key        | Select your signing key                              |

Token settings (Advanced protocol settings):

| Setting                | Value                        |
| ---------------------- | ---------------------------- |
| Access Token validity  | `minutes=10`                 |
| Refresh Token validity | `days=30`                    |
| Scopes                 | `openid`, `email`, `profile` |

**Authentik application:**

| Setting    | Value                            |
| ---------- | -------------------------------- |
| Name       | `Nextcloud`                      |
| Slug       | `nextcloud`                      |
| Provider   | `nextcloud`                      |
| Launch URL | `https://cloud.yggdrasil.mia.cx` |

**Nextcloud configuration:**

1. Enable the OIDC app:

```bash
kubectl exec -it -n nextcloud deploy/nextcloud -- su -s /bin/bash www-data -c "php occ app:enable user_oidc"
```

2. Add the provider:

```bash
kubectl exec -it -n nextcloud deploy/nextcloud -- su -s /bin/bash www-data -c "php occ user_oidc:provider:create \
  --identifier='authentik' \
  --clientid='nextcloud' \
  --clientsecret='YOUR_CLIENT_SECRET' \
  --discoveryuri='https://id.mia.cx/application/o/nextcloud/.well-known/openid-configuration' \
  --unique-uid='0' \
  --check-bearer='0' \
  --send-id-token-hint='1' \
  Authentik"
```

Or configure in Settings → Administration → SSO & SAML authentication:

| Setting            | Value                                                                          |
| ------------------ | ------------------------------------------------------------------------------ |
| Identifier         | `authentik`                                                                    |
| Client ID          | `nextcloud`                                                                    |
| Client Secret      | (from secret)                                                                  |
| Discovery endpoint | `https://id.mia.cx/application/o/nextcloud/.well-known/openid-configuration` |

3. Optional -- disable password login for SSO-only:

```bash
kubectl exec -it -n nextcloud deploy/nextcloud -- su -s /bin/bash www-data -c \
  "php occ config:app:set --value=0 user_oidc allow_multiple_user_backends"
```

## Storage

| PVC            | Mount                | Source              |
| -------------- | -------------------- | ------------------- |
| Longhorn (app) | `/var/www/html`      | Local block storage |
| Longhorn (db)  | MariaDB data dir     | Local block storage |
| NFS            | `/var/www/html/data` | NVMe critical data  |

## Data Migration

From an existing Nextcloud instance:

```bash
# 1. Export database from old server
mysqldump -u nextcloud -p nextcloud > nextcloud.sql

# 2. Copy SQL to new MariaDB pod
kubectl cp nextcloud.sql nextcloud/nextcloud-mariadb-0:/tmp/

# 3. Import
kubectl exec -it -n nextcloud nextcloud-mariadb-0 -- mariadb -u nextcloud -p nextcloud < /tmp/nextcloud.sql

# 4. Copy data directory to NFS
rsync -av old-server:/path/to/data/ /mnt/media/cloud/

# 5. Scan files
kubectl exec -it -n nextcloud deploy/nextcloud -- su -s /bin/bash www-data -c "php occ files:scan --all"

# 6. Fix permissions if needed
kubectl exec -it -n nextcloud deploy/nextcloud -- chown -R www-data:www-data /var/www/html/data
```
