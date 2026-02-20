---
title: Traefik Internal (Secondary Instance)
---

# Secondary Traefik for Internal-Only Services

A **planned** secondary Traefik instance dedicated to internal-only traffic (LAN, Netbird overlay), instead of relying on the internal-only IP allowlist middleware on the primary Traefik.

## Motivation

- **Physical separation** — Different process, config, and network exposure; internal traffic never touches the external Traefik.
- **Failure isolation** — Misconfig or crash on the primary Traefik does not affect internal services.
- **Simpler security boundary** — Internal Traefik listens only on ClusterIP (or a dedicated internal VIP); no LoadBalancer, no public exposure.
- **Defense in depth** — Avoids relying on middleware that could misconfigure or default to allow.

## Scope

- **In scope:** Deploy a second Traefik instance (e.g. `traefik-internal` Helm release) in a dedicated namespace; ClusterIP Service only; IngressRoutes for internal services (panel, Radarr, Sonarr, etc.); DNS / split-horizon so internal clients reach the internal instance.
- **Out of scope:** Duplicating TLS setup (internal can reuse existing certs or a separate store); changes to Authentik forward-auth (internal routes can still use it if needed).

## Current State

- Primary Traefik handles all ingress; internal services use the `internal-only` middleware (IP allowlist).
- See [Traefik](../../infrastructure/traefik.md) for existing config; internal-only middleware lives in `argocd/traefik/middlewares.yaml`.

## Target Design

| Component        | Primary Traefik      | Internal Traefik        |
| ---------------- | -------------------- | ----------------------- |
| Namespace        | `kube-system`        | `traefik-internal`      |
| Service type     | LoadBalancer (VIP)   | ClusterIP only          |
| Entrypoints      | web (80), websecure (443) | Same ports, different Service |
| IngressRoutes    | Public + some internal (with middleware) | Internal-only routes |
| Providers        | Kubernetes CRD       | Same; watch selected namespaces or labels |

Internal clients (LAN, Netbird) resolve `*.yggdrasil.mia.cx` via split-horizon DNS to the internal Traefik Service IP or a dedicated internal ingress host. External clients continue to use the primary Traefik VIP.

## Decisions to Document

- Which namespace(s) the internal Traefik watches for IngressRoutes (all vs. labeled).
- How internal DNS points to the internal instance (ClusterIP vs. NodePort for Netbird/VPN clients).
- Whether to migrate existing internal IngressRoutes in bulk or incrementally.

## Related Docs

- [Traefik](../../infrastructure/traefik.md) — Primary Traefik config, middlewares, TLS.
- [DNS](../../infrastructure/dns.md) — Split-horizon resolution for `*.yggdrasil.mia.cx`.
