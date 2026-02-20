---
title: Roadmaps
---

# Roadmaps

Plans and backlogs by category. Each roadmap is a living doc; add new ones here as you create them.

## By category

| Category       | Roadmap                    | Description                                                                 |
| -------------- | -------------------------- | --------------------------------------------------------------------------- |
| Infrastructure | [Node onboarding](./infrastructure/node-onboarding.md) | PXE boot, cloud-init, OpenTofu: add Echo mini-PCs to the cluster with one code change. |
| Infrastructure | [Cloud-init images](./infrastructure/cloud-init-images.md) | Catalog of cloud-init images for Proxmox, K3s, Wings VM, and LXCs (Storage, Netbird, Authentik legacy). |
| Infrastructure | [Resilience nodes](./infrastructure/resilience-nodes.md) | Hosted nodes (e.g. Hetzner/OVH VPS) to keep K8s + GitOps alive; Longhorn excluded so configs only, no PVC data. |
| Infrastructure | [Traefik internal](./infrastructure/traefik-internal.md)   | Secondary Traefik instance for internal-only services; replaces reliance on internal-only middleware. |
| Services       | [Self-hosted services](./services/self-hosted.md)       | Candidate services to run (wiki, music, finance, analytics) with why and effort. |
| Misc           | [Project ideas](./project-ideas.md)                    | Future client-side / side projects to revisit (e.g. Jelly-Clipper as browser extension). |

## See also

- [Migration](../operations/migration.md) — Phased migration (Docker → K3s); Phase 6 uses the node onboarding roadmap.
- [Operations](../operations/index.md) — Runbooks, migration, and day-to-day ops.
