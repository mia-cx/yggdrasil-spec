---
title: Architecture
---

# Architecture Overview

## Hardware

### Workstation (Primary Node)

- **CPU:** Ryzen 9 7950x (16c/32t)
- **RAM:** 96GB DDR5-5200
- **GPU:** RTX 3070 (passthrough to Workstation VM)
- **NVMe:** Slot 1 boot, Slot 2 2TB data (`/mnt/nvme`), Slots 3-4 future expansion
- **HDDs:** 4x8TB at `/mnt/disk1-4` (MergerFS pool, upgrading to 22TB over time)
- **Network:** 2.5GbE + 10GbE NICs

### VMs and Containers

| Name | Type | Resources | IP | VMID | Purpose |
|------|------|-----------|-----|------|---------|
| Storage LXC | LXC | 1GB RAM | 10.0.1.2 | 1002 | MergerFS + NFS exports |
| Authentik LXC | LXC | 1-2GB RAM | 10.0.1.3 | 1003 | Identity provider (SSO) |
| K3s VM | VM | 16GB RAM | 10.0.1.4 | 1004 | Kubernetes workloads |
| Netbird LXC | LXC | 512MB-1GB | 10.0.1.5 | 1005 | Overlay network management |
| Wings VM | VM | 4-8GB RAM | 10.0.1.6 | 1006 | Pelican/Pterodactyl game servers |
| Workstation VM | VM | 48GB RAM | 10.0.3.1 | 3001 | Gaming/Blender + GPU |

### Old Server

Download disks, will join Proxmox cluster after migration.

### Future: Mini-PCs

16-32GB RAM each, Intel N100/N305 recommended for QuickSync transcoding.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     Proxmox Host (10.0.1.1)                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ Storage LXC  │  │ Authentik    │  │ Netbird LXC  │      │
│  │ (10.0.1.2)   │  │ LXC          │  │ (10.0.1.5)   │      │
│  │              │  │ (10.0.1.3)   │  │              │      │
│  │ MergerFS     │  │              │  │ WireGuard    │      │
│  │ NFS exports  │  │ OIDC/SSO     │  │ Management   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                             │
│  ┌────────────────────────────┐  ┌──────────────────────┐  │
│  │ K3s VM (10.0.1.4)          │  │ Workstation VM       │  │
│  │ VMID: 1004                 │  │ (10.0.3.1)           │  │
│  │ Hydra cluster              │  │ VMID: 3001           │  │
│  │ ├── Traefik                │  │ RTX 3070 passthrough │  │
│  │ ├── Longhorn               │  │ Gaming / Blender     │  │
│  │ ├── Jellyfin               │  │                      │  │
│  │ └── ...services            │  │                      │  │
│  └────────────────────────────┘  └──────────────────────┘  │
│                                                             │
│  Storage: /mnt/nvme (2TB) + /mnt/disk1-4 (4x8TB HDDs)      │
└─────────────────────────────────────────────────────────────┘
```

## Related

- [Naming Scheme](./naming.md)
- [Network Allocation](./network.md)
- [Key Decisions](./decisions.md)
