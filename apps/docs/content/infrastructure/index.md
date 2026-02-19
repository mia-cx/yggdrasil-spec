---
title: Infrastructure
---

# Infrastructure

Core platform components that underpin all services.

## Components

| Component                             | Location    | Purpose                        |
| ------------------------------------- | ----------- | ------------------------------ |
| [Storage LXC](./storage.md)           | 10.0.1.2    | MergerFS pool + NFS exports    |
| [Kubernetes (Hydra)](./kubernetes.md) | 10.0.1.3    | K3s container orchestration    |
| [Workload placement](./workload-placement.md) | K3s nodes | Node affinity (critical vs media) |
| [ArgoCD](./argocd.md)                 | K3s         | GitOps continuous delivery     |
| [Authentik](./authentik.md)           | K3s         | Identity provider + SSO        |
| [Netbird](./netbird.md)               | 10.0.1.4    | Overlay network management     |
| [Traefik](./traefik.md)               | ArgoCD      | Ingress controller + TLS       |
| [DNS](./dns.md)                       | Multi-layer | Split-horizon DNS resolution   |
| [Data Layer](./data-layer.md)         | K3s         | PostgreSQL, Redis, Vaultwarden |

## Dependency Order

```
1. Proxmox Host
   └── Host storage mounts (/mnt/nvme, /mnt/sda1-sdd1)

2. Storage LXC (10.0.1.2)
   └── MergerFS + NFS exports

3. K3s VM (10.0.1.3)
   └── kube-vip → K3s → Longhorn → cert-manager

4. ArgoCD
   └── GitOps bootstrap (argocd/_apps/root.yaml)

5. Authentik (K3s)
   └── Helm chart → PostgreSQL + Redis + IdP

6. Netbird LXC (10.0.1.4)
   └── Management server (uses Authentik OIDC)

7. Traefik (K3s bundled)
   └── TLS certificates + middlewares

8. DNS (Cloudflare + CoreDNS)
   └── Split-horizon resolution

9. Wings VM (10.0.1.6)
   └── Docker + Wings daemon (game servers)

10. Netbird exit nodes (K3s DaemonSet)
    └── Connects to Netbird management
```

## Host Storage Layout

```
Proxmox Host
├── /mnt/nvme (ext4, future ZFS)
│   ├── databases/
│   ├── configs/
│   └── critical/
│
└── /mnt/sda1-sdd1 (ext4 HDDs)
    └── Bind-mounted to Storage LXC
        └── MergerFS → /mnt/media
```
