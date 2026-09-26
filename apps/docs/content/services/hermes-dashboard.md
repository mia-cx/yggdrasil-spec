---
title: Hermes Dashboard
---

# Hermes Dashboard

## Migration planning

The [accepted K3s integration](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743564646) keeps the existing Hermes browser URLs and native Hecate OIDC flow. Existing access remains until NetBird passes its stability pilot and Mia approves the service's cutover.

Private Traefik will use explicit NetworkEgress paths to the dashboard listener on TCP 9119 and the MCP callback listeners on TCP 18765 and 18766. Dashboard `/auth/callback` remains on the dashboard listener. These backend targets identify the Hermes mesh peer rather than its browser-facing aliases.

Hermes reaches the Microsoft 365 MCP Service through a restricted NetworkResource. Keep machine `/mcp`, metadata, and `/token` traffic separate from the private browser `/authorize` route. Verify the existing URL mapping, redirect registrations, and token refresh before retiring the old machine VIP path.

The [connection contract](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743163099) records the callers and DNS requirements. The deployment notes below describe the current arrangement, not an already-private deployment.

## Overview

| Property  | Value                                    |
| --------- | ---------------------------------------- |
| Type      | External service proxied through Traefik |
| Host      | `athena-hephaestus`                      |
| Backend   | `10.0.3.2:9119`                          |
| Namespace | `hermes`                                 |
| URL       | `https://hermes.yggdrasil.mia.cx`        |
| Auth      | Hermes dashboard OIDC via Authentik      |
| Storage   | On host (`~/.hermes`)                    |

Hermes Dashboard runs directly on `athena-hephaestus` as a systemd user service. K3s exposes it through a selector-less Service and EndpointSlice, then Traefik terminates TLS and forwards traffic to `10.0.3.2:9119`.

## Manifests

| File                                        | Purpose                                          |
| ------------------------------------------- | ------------------------------------------------ |
| `argocd/_apps/hermes-dashboard.yaml`        | ArgoCD Application for companion manifests       |
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
