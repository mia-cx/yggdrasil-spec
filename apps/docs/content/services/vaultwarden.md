---
title: Vaultwarden
---

# Vaultwarden

## Overview

| Property  | Value                                 |
| --------- | ------------------------------------- |
| Image     | `vaultwarden/server:1.36.0`           |
| Port      | 80                                    |
| Namespace | `vaultwarden`                         |
| URL       | `https://warden.mia.cx`               |
| Storage   | Longhorn (data/db), NFS (attachments) |

Self-hosted Bitwarden-compatible password manager. Uses native OIDC SSO for login convenience -- the master password remains the vault encryption key.

> **Important:** Do not use Authentik forward-auth middleware on Vaultwarden. The master password is the vault encryption key, not just authentication -- Vaultwarden must handle its own auth flow.

## Manifests

| File                                   | Purpose                                |
| -------------------------------------- | -------------------------------------- |
| `argocd/vaultwarden/storage.yaml`      | Namespace, PV/PVC for Longhorn + NFS   |
| `argocd/vaultwarden/deployment.yaml`   | Pod, Service                           |
| `argocd/vaultwarden/ingressroute.yaml` | Traefik IngressRoute (no forward-auth) |

## Deployment

```bash
# Create NFS directory for attachments
ssh 10.0.1.2 'sudo mkdir -p /mnt/nvme/vaultwarden/attachments && sudo chmod 777 /mnt/nvme/vaultwarden/attachments'

# Create namespace
kubectl create namespace vaultwarden

# Create secrets (push credentials: https://bitwarden.com/host/)
kubectl create secret generic vaultwarden-secrets \
  --namespace vaultwarden \
  --from-literal=ADMIN_TOKEN="$(openssl rand -base64 48)" \
  --from-literal=PUSH_INSTALLATION_ID="your-installation-id" \
  --from-literal=PUSH_INSTALLATION_KEY="your-installation-key" \
  --from-literal=SSO_CLIENT_SECRET="your-authentik-client-secret"

# Apply all manifests
kubectl apply -f argocd/vaultwarden/
```

## Configuration

### SSO with Authentik

**Authentik provider:**

1. Applications → Providers → Create → OAuth2/OpenID Provider

| Setting            | Value                                                |
| ------------------ | ---------------------------------------------------- |
| Name               | `vaultwarden`                                        |
| Authorization flow | `default-provider-authorization-implicit-consent`    |
| Client ID          | `vaultwarden`                                        |
| Client Secret      | (copy to K8s secret)                                 |
| Redirect URIs      | `https://warden.mia.cx/identity/connect/oidc-signin` |
| Signing Key        | Select your signing key                              |

**Critical token settings** (Advanced protocol settings):

| Setting                | Value                                          |
| ---------------------- | ---------------------------------------------- |
| Access Token validity  | `minutes=10` (must be >5min)                   |
| Refresh Token validity | `days=30`                                      |
| Scopes                 | `openid`, `email`, `profile`, `offline_access` |

Without `offline_access` and proper token lifetimes, SSO login will fail immediately after authentication.

**Authentik application:**

| Setting    | Value                   |
| ---------- | ----------------------- |
| Name       | `Vaultwarden`           |
| Slug       | `vaultwarden`           |
| Provider   | `vaultwarden`           |
| Launch URL | `https://warden.mia.cx` |

**Environment variables:**

```yaml
- name: SSO_ENABLED
  value: "true"
- name: SSO_ONLY
  value: "false" # Allow password login alongside SSO
- name: SSO_CLIENT_ID
  value: "vaultwarden"
- name: SSO_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: vaultwarden-secrets
      key: SSO_CLIENT_SECRET
- name: SSO_AUTHORITY
  value: "https://auth.mia.cx/application/o/vaultwarden/"
```

### User Onboarding

1. Admin invites user via `/admin` panel
2. User clicks invite link, logs in via SSO
3. After SSO authentication, user sets their master password
4. Master password encrypts the vault (SSO is only for authentication)

### Admin Panel

Access at `https://warden.mia.cx/admin` with the generated token:

```bash
kubectl get secret vaultwarden-secrets -n vaultwarden \
  -o jsonpath='{.data.ADMIN_TOKEN}' | base64 -d
```

## Storage

| PVC             | Mount               | Source                            |
| --------------- | ------------------- | --------------------------------- |
| Longhorn (data) | `/data`             | SQLite database (needs good IOPS) |
| NFS             | `/data/attachments` | Bulk attachment storage           |

## Data Migration

From an existing Bitwarden/Vaultwarden:

**Via export/import:**

1. Export from old instance (Settings → Export vault)
2. Import in new instance (Settings → Import data)

**Via direct copy:**

```bash
# Find Longhorn volume path
kubectl get pvc -n vaultwarden vaultwarden-data-pvc -o jsonpath='{.spec.volumeName}'
# SSH to node, copy db.sqlite3 to /var/lib/longhorn/replicas/<volume>/

# For attachments, copy to NFS:
scp -r old-server:/path/to/attachments/* 10.0.1.2:/mnt/nvme/vaultwarden/attachments/
```
