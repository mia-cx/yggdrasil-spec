---
title: Jellyfin
---

# Jellyfin

Media streaming server with SSO via Authentik.

## Limitations

- Cannot be load-balanced (session state in memory)
- Dedicate one node (preferably with Intel QuickSync for transcoding)

## SSO Setup

### Install Plugin

Install `jellyfin-plugin-sso` from the plugin catalog.

### Authentik Application

1. Create OAuth2/OpenID Provider in Authentik
2. Redirect URI: `https://jellyfin.yggdrasil.mia.cx/sso/OID/redirect/Authentik`
3. Copy Client ID

### Jellyfin SSO Config

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

## Group-Based Permissions

| Authentik Group | Jellyfin Role |
|-----------------|---------------|
| media-users | User |
| media-admin | Administrator |

## User Onboarding Flow

1. Create user in Authentik, add to `media-users` group
2. User connects to Netbird (also via Authentik)
3. User visits jellyfin.yggdrasil.mia.cx
4. Clicks "Sign in with Authentik"
5. Account auto-created with correct permissions

## Storage

Mount media NFS volume:

```yaml
volumes:
  - name: media
    persistentVolumeClaim:
      claimName: media-nfs-pvc
```

Mount path: `/media`

## IngressRoute

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: jellyfin
  namespace: media
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`jellyfin.yggdrasil.mia.cx`)
      kind: Rule
      services:
        - name: jellyfin
          port: 8096
  tls:
    secretName: wildcard-tls
```

## Hardware Transcoding

For Intel QuickSync (on mini-PC node):

```yaml
resources:
  limits:
    gpu.intel.com/i915: 1
```

Node selector:

```yaml
nodeSelector:
  kubernetes.io/hostname: mpc-1
```
