---
title: Infrastructure
---

# Infrastructure Setup

This section covers the core infrastructure components that run outside of Kubernetes.

## Components

| Component | Location | Purpose |
|-----------|----------|---------|
| [[storage|Storage LXC]] | 10.0.1.2 | MergerFS pool + NFS exports |
| [[authentik|Authentik LXC]] | 10.0.1.3 | Identity provider + SSO |
| [[kubernetes|K3s (Hydra)]] | 10.0.1.4 | Container orchestration |
| [[netbird|Netbird LXC]] | 10.0.1.5 | Overlay network management |

## Dependency Order

```
1. Proxmox Host
   └── Host storage mounts (/mnt/nvme, /mnt/disk1-4)

2. Storage LXC (10.0.1.2)
   └── MergerFS + NFS exports

3. Authentik LXC (10.0.1.3)
   └── PostgreSQL + Redis + Authentik (IdP foundation)

4. K3s VM (10.0.1.4)
   └── kube-vip → K3s → Longhorn → cert-manager

5. Netbird LXC (10.0.1.5)
   └── Management server (uses Authentik OIDC)

6. Wings VM (10.0.1.6)
   └── Docker + Wings daemon (game servers)

7. Netbird exit nodes (K3s DaemonSet)
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
└── /mnt/disk1-4 (ext4 HDDs)
    └── Bind-mounted to Storage LXC
        └── MergerFS → /mnt/media
```
