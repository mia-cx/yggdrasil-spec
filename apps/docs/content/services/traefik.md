---
title: Traefik
---

# Traefik

Ingress controller and reverse proxy, bundled with K3s.

## Overview

- Pre-installed with K3s
- VIP: 10.0.128.2 (via kube-vip)
- Router forwards ports 80/443 to this IP

## TLS Certificates

Using cert-manager with Cloudflare DNS-01 for wildcard certificates.

### Cloudflare ClusterIssuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your@email.com
    privateKeySecretRef:
      name: letsencrypt-account-key
    solvers:
      - dns01:
          cloudflare:
            email: your@email.com
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

### Wildcard Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-yggdrasil
  namespace: traefik
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
    - "*.yggdrasil.mia.cx"
    - "yggdrasil.mia.cx"
```

## Authentik Forward Auth Middleware

Protects routes requiring authentication:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik
  namespace: traefik
spec:
  forwardAuth:
    address: http://authentik-server.authentik/outpost.goauthentik.io/auth/traefik
    trustForwardHeader: true
    authResponseHeaders:
      - X-authentik-username
      - X-authentik-groups
      - X-authentik-email
```

## IngressRoute Examples

### Public service (no auth)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: jellyfin
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

### Protected service (requires auth)

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: sonarr
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`sonarr.yggdrasil.mia.cx`)
      kind: Rule
      middlewares:
        - name: authentik  # Requires login
      services:
        - name: sonarr
          port: 8989
  tls:
    secretName: wildcard-tls
```

## Extracting Certificates

For use outside K3s (e.g., Proxmox):

```bash
kubectl get secret wildcard-tls -n traefik -o jsonpath='{.data.tls\.crt}' | base64 -d > fullchain.pem
kubectl get secret wildcard-tls -n traefik -o jsonpath='{.data.tls\.key}' | base64 -d > privkey.pem
```
