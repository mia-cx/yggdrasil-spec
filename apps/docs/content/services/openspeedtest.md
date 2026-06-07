---
title: OpenSpeedTest
---

# OpenSpeedTest

## Overview

| Property  | Value                         |
| --------- | ----------------------------- |
| Image     | `openspeedtest/latest:latest` |
| Port      | 3000                          |
| Namespace | `speedtest`                   |
| Chart     | `bjw-s/app-template` (v3)     |
| URL       | `https://speedtest.mia.cx`    |
| Storage   | None                          |

Browser-based bandwidth test for checking public ingress and home uplink/downlink performance.

## Manifests

| File                                     | Purpose                                 |
| ---------------------------------------- | --------------------------------------- |
| `argocd/_apps/openspeedtest.yaml`        | ArgoCD Application (bjw-s/app-template) |
| `argocd/openspeedtest/values.yaml`       | Helm values overrides                   |
| `argocd/openspeedtest/ingressroute.yaml` | Public Traefik IngressRoute             |

## Deployment Notes

- Public route: `speedtest.mia.cx`
- No Authentik middleware; the service is intentionally public.
- TLS is served by Traefik's default wildcard certificate.
- Public DNS uses the existing Cloudflare CNAME chain to the site DDNS record.
