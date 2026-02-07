---
title: Traefik
---

# Traefik

## Overview

| Property  | Value                     |
| --------- | ------------------------- |
| Type      | K8s (bundled with K3s)    |
| Namespace | `kube-system`             |
| VIP       | 10.0.128.2 (via kube-vip) |
| Ports     | 80, 443                   |
| Storage   | local-path (ACME cache)   |

Ingress controller and reverse proxy bundled with K3s. The router forwards ports 80/443 to the Traefik VIP, which terminates TLS and routes requests to backend services.

## Prerequisites

- K3s installed (Traefik ships as a default component)
- kube-vip configured with VIP `10.0.128.2`
- Router port-forwarding 80/443 to the VIP

## Setup

### TLS via cert-manager

Install cert-manager for automated wildcard certificates using Cloudflare DNS-01:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
kubectl wait --for=condition=Available -n cert-manager deployment/cert-manager-webhook --timeout=120s
```

Create the Cloudflare API token secret (requires `Zone:DNS:Edit` on all zones):

```bash
kubectl create secret generic cloudflare-api-token \
  -n cert-manager \
  --from-literal=api-token="YOUR_CLOUDFLARE_API_TOKEN"
```

Deploy ClusterIssuer, wildcard Certificate, and default TLS store:

```bash
kubectl apply -f argocd/cert-manager/
kubectl apply -f argocd/traefik/tls-store.yaml
```

### Verify Certificate

```bash
kubectl get certificate -n kube-system
kubectl describe certificate wildcard-certs -n kube-system
kubectl get secret wildcard-tls -n kube-system
```

## Configuration

### Middlewares

Both middlewares live in `kube-system` so any namespace can reference them.

```bash
kubectl apply -f argocd/traefik/middlewares.yaml
```

**internal-only** -- `ipAllowList` restricting access to LAN (`10.0.0.0/8`) and Netbird overlay (`100.64.0.0/10`). Rejects public internet requests.

```yaml
middlewares:
  - name: internal-only
    namespace: kube-system
```

**authentik** -- Forward-auth to the Authentik outpost for SSO-protected routes.

```yaml
middlewares:
  - name: authentik
    namespace: kube-system
```

### IngressRoute Examples

**Public service (no auth):**

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

**Protected service (internal + auth):**

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
        - name: internal-only
          namespace: kube-system
      services:
        - name: sonarr
          port: 8989
  tls: {}
```

### Extracting Certificates

For use outside K3s (e.g., Proxmox UI):

```bash
kubectl get secret wildcard-tls -n kube-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > fullchain.pem
kubectl get secret wildcard-tls -n kube-system \
  -o jsonpath='{.data.tls\.key}' | base64 -d > privkey.pem
```

## Verification

```bash
# Check Traefik pod
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# List all IngressRoutes
kubectl get ingressroutes -A

# Check certificate status
kubectl get certificate -n kube-system
```
