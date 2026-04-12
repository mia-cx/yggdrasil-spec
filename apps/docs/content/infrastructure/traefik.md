---
title: Traefik
---

# Traefik

## Overview

| Property  | Value                     |
| --------- | ------------------------- |
| Type      | ArgoCD (traefik/traefik Helm chart) |
| Namespace | `kube-system`             |
| VIP       | 10.0.128.2 (via kube-vip) |
| Ports     | 80, 443                   |
| Replicas  | 2 (spread across nodes)   |
| Storage   | local-path (ACME cache)   |

Ingress controller and reverse proxy. Deployed via ArgoCD using the official [traefik/traefik](https://github.com/traefik/traefik-helm-chart) Helm chart (replaces K3s built-in Traefik). The router forwards ports 80/443 to the Traefik VIP, which terminates TLS and routes requests to backend services.

## Prerequisites

- K3s installed with **built-in Traefik disabled** (`--disable=traefik` on all server nodes)
- kube-vip configured with VIP `10.0.128.2`
- Router port-forwarding 80/443 to the VIP
- ArgoCD installed and root Application synced

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

Traefik is managed by ArgoCD via **`argocd/_apps/traefik.yaml`**. Values live in **`argocd/traefik/values.yaml`**; companion manifests (middlewares, TLS store) are in the same directory. Push changes to the repo and ArgoCD auto-syncs.

To disable K3s built-in Traefik before migrating:

```bash
# Add to /etc/default/k3s (or equivalent):
K3S_SERVER_ARGS="--disable=traefik"

# Restart K3s on all server nodes
sudo systemctl restart k3s
```

After the built-in Traefik is gone, the ArgoCD `traefik` Application deploys the Helm chart. There will be a brief period without ingress until the new Traefik is running.

### Origin IP (real client IP to backends)

So backends (e.g. Nextcloud) and forward-auth (e.g. Authentik) see the real client IP, two things are configured:

1. **Preserve client IP at the Service** — `service.spec.externalTrafficPolicy: Local` in `values.yaml`. Without this, the node that receives traffic SNATs it, so Traefik sees the node IP and forwards that in `X-Forwarded-For`. With `Local`, the source IP is preserved and Traefik sets `X-Forwarded-For` to the real client. _Caveat:_ `Local` forwards only to pods on the node that received the request, so kube-vip must advertise the VIP from a node with a local Traefik pod. That is why kube-vip runs with `svc_election=true` and Traefik runs as a 2-replica Deployment spread across hostnames.
2. **Trust upstream proxies** — When a proxy in front of Traefik (e.g. router, another LB) sends `X-Forwarded-For`, Traefik must trust it. The chart does not expose entrypoint `forwardedHeaders` as values, so this is set via `additionalArguments` in `values.yaml`. CIDRs match LAN and Netbird overlay.

Backends must also trust the proxy: e.g. Nextcloud `trusted_proxies` includes the Traefik pod CIDR (`10.0.0.0/8` in our values) and `forwarded_for_headers` → `HTTP_X_FORWARDED_FOR`. After changing values, push to the repo; ArgoCD will roll the Traefik deployment.

### Middlewares

Both middlewares live in `kube-system` so any namespace can reference them. Deployed by ArgoCD with the `traefik` Application. To apply manually:

```bash
kubectl apply -f argocd/traefik/middlewares.yaml
```

**internal-only** -- `ipAllowList` restricting access to LAN (`10.0.0.0/8`) and Netbird overlay (`100.64.0.0/10`). Rejects public internet requests. It uses the connection **remote address** (the source IP of the TCP connection to Traefik), not `X-Forwarded-For`.

**If 5G traffic still gets through:** If your router preserves source IP (e.g. you see your public IP in Nextcloud) but internal-only still allows requests from 5G, the connection Traefik receives may be from an internal IP (e.g. another NAT hop, or traffic taking a different path). Verify what Traefik sees by enabling access logs (see [Verify client IP](#verify-client-ip-access-logs) below) and checking the logged client IP for a request from 5G. If the log shows 10.x or 100.64.x, something in front of Traefik is NATing or the path is not direct. If the log shows your public IP but you still get through, the middleware may not be applied (check the IngressRoute). If the router does SNAT (connection source = router LAN IP), configure the port forward to preserve client IP, or don't rely on internal-only for that path and use the **authentik** middleware instead.

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

### Verify client IP (access logs)

To see which client IP Traefik uses for each request (the same IP used by internal-only), enable access logs. Logs are configured in `values.yaml` (e.g. `logs.access.enabled: true`, optional `format: json` and `fields.headers` for X-Forwarded-_). Do not put `--logs._`in`additionalArguments`— the Traefik binary can reject them and crash with “field not found, node: logs”. If you disabled access logs, re-enable in`values.yaml` with:

```yaml
logs:
  access:
    enabled: true
```

Push the values change; ArgoCD will roll the Traefik deployment. Then open a route (e.g. Radarr) from your phone on 5G and check the Traefik pod logs:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik -c traefik --tail=50
```

Look for the request; the logged client IP is what internal-only and the backend see. If it shows 10.x or 100.64.x when you're on 5G, the connection to Traefik is coming from an internal hop. If it shows your public IP, internal-only should be blocking; if you still get through, confirm the IngressRoute has the internal-only middleware applied. Turn access logs off again after debugging by removing the `logs.access` block.

### Inspect requests to a host (e.g. cloud.mia.cx)

With access logs enabled (default CLF format), recent requests show `ClientAddr` (the IP Traefik sees) and the request line. To see only lines for a given host:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik -c traefik --tail=200 2>/dev/null \
  | grep cloud.mia.cx
```

`values.yaml` already sets `logs.access.format: json` and `logs.access.fields.headers.names` for X-Forwarded-For / X-Forwarded-Proto when access logs are enabled. If the chart does not support these keys, simplify to `logs.access.enabled: true` only; invalid values can put Traefik in CrashLoopBackOff.

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
