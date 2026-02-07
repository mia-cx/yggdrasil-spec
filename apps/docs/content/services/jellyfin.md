---
title: Jellyfin
---

# Jellyfin

## Overview

| Property  | Value                                       |
| --------- | ------------------------------------------- |
| Image     | `docker.io/jellyfin/jellyfin:10`            |
| Port      | 8096                                        |
| Namespace | `media`                                     |
| Chart     | `bjw-s/app-template` (v3)                   |
| URL       | `https://jellyfin.yggdrasil.mia.cx`         |
| Storage   | Longhorn (config, cache), NFS (media, nvme) |

Media streaming server with SSO via Authentik. Cannot be load-balanced (session state in memory) -- dedicate one node, preferably with Intel QuickSync for hardware transcoding.

## Architecture

Jellyfin reads from the shared NFS media library (MergerFS 29Ti). Config and cache are stored on Longhorn for fast local I/O.

## Manifests

| File                                | Purpose                                            |
| ----------------------------------- | -------------------------------------------------- |
| `argocd/jellyfin/values.yaml`       | Helm values (image, resources, persistence)        |
| `argocd/jellyfin/storage.yaml`      | Namespace, NFS PVCs for media library              |
| `argocd/jellyfin/ingressroute.yaml` | Traefik IngressRoute with internal-only middleware |

## Deployment

```bash
kubectl apply -f argocd/jellyfin/storage.yaml
kubectl apply -f argocd/jellyfin/ingressroute.yaml

helm repo add bjw-s https://bjw-s-labs.github.io/helm-charts
helm repo update
helm install jellyfin bjw-s/app-template \
  --namespace media \
  -f argocd/jellyfin/values.yaml
```

## Configuration

### SSO with Authentik

**Install plugin:** Install `jellyfin-plugin-sso` from the plugin catalog.

**Authentik application:**

1. Create OAuth2/OpenID Provider in Authentik
2. Redirect URI: `https://jellyfin.mia.cx/sso/OID/redirect/Authentik`
3. Copy Client ID

**Jellyfin SSO config:**

```yaml
Providers:
  - Name: Authentik
    OidcClientId: jellyfin
    OidcAuthority: https://auth.yggdrasil.mia.cx/application/o/jellyfin/
    EnableAuthorization: true
    Roles:
      - AuthRole: media-users
        AppRole: User
      - AuthRole: media-admin
        AppRole: Administrator
```

### Group-Based Permissions

| Authentik Group | Jellyfin Role |
| --------------- | ------------- |
| media-users     | User          |
| media-admin     | Administrator |

### User Onboarding

1. Create user in Authentik, add to `media-users` group
2. User connects to Netbird (also via Authentik)
3. User visits `https://jellyfin.yggdrasil.mia.cx`
4. Clicks "Sign in with Authentik"
5. Account auto-created with correct permissions

### Hardware Transcoding

When Intel QuickSync nodes are available, uncomment the `gpu.intel.com/i915` limit and `nodeSelector` in `values.yaml`. Requires the [Intel GPU device plugin](https://github.com/intel/intel-device-plugins-for-kubernetes).

## Storage

| PVC               | Mount     | Source                   |
| ----------------- | --------- | ------------------------ |
| Longhorn (config) | `/config` | Local block storage      |
| Longhorn (cache)  | `/cache`  | Local block storage      |
| `media-nfs-pvc`   | `/media`  | NFS (MergerFS, 29Ti)     |
| `nvme-nfs-pvc`    | `/nvme`   | NFS (NVMe critical data) |
