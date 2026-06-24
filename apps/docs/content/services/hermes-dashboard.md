---
title: Hermes Dashboard
---

# Hermes Dashboard

## Overview

| Property  | Value                                  |
| --------- | -------------------------------------- |
| Type      | External service proxied through Traefik |
| Host      | `athena-hephaestus`                    |
| Backend   | `10.0.3.2:9119`                        |
| Namespace | `hermes`                               |
| URL       | `https://hermes.yggdrasil.mia.cx`      |
| Auth      | Hermes dashboard OIDC via Authentik    |
| Storage   | On host (`~/.hermes`)                  |

Hermes Dashboard runs directly on `athena-hephaestus` as a systemd user service. K3s exposes it through a selector-less Service and EndpointSlice, then Traefik terminates TLS and forwards traffic to `10.0.3.2:9119`.

## Manifests

| File                                      | Purpose                                           |
| ----------------------------------------- | ------------------------------------------------- |
| `argocd/_apps/hermes-dashboard.yaml`      | ArgoCD Application for companion manifests        |
| `argocd/hermes-dashboard/ingressroute.yaml` | Service, EndpointSlice, and Traefik IngressRoute |

## Deployment Notes

- Public route: `hermes.yggdrasil.mia.cx`
- TLS is served by Traefik's default wildcard certificate.
- No Traefik Authentik forward-auth middleware is attached. Hermes Dashboard owns its own OIDC flow and uses Authentik as the OIDC provider.
- Hermes should be configured with `dashboard.public_url: https://hermes.yggdrasil.mia.cx` so OIDC callback URLs are generated correctly.
- Authentik redirect URI should be `https://hermes.yggdrasil.mia.cx/auth/callback`.

## Host Service

The dashboard process should be kept alive on `athena-hephaestus` with the `hermes-dashboard` user service:

```bash
systemctl --user status hermes-dashboard --no-pager
journalctl --user -u hermes-dashboard -n 100 --no-pager
```
