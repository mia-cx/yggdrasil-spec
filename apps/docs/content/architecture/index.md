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
- **HDDs:** 4x8TB at `/mnt/sda1`-`/mnt/sdd1` (MergerFS pool, upgrading to 22TB over time)
- **Network:** 2.5GbE + 10GbE NICs

### VMs and Containers

| Name           | Type | Resources | IP       | VMID | Purpose                          |
| -------------- | ---- | --------- | -------- | ---- | -------------------------------- |
| Storage LXC    | LXC  | 1GB RAM   | 10.0.1.2 | 1002 | MergerFS + NFS exports           |
| K3s VM         | VM   | 16GB RAM  | 10.0.1.3 | 1003 | Kubernetes workloads             |
| NetBird VM     | VM   | 4GB RAM   | 10.0.1.4 | 1004 | Overlay network management       |
| Wings VM       | VM   | 4-8GB RAM | 10.0.1.6 | 1006 | Pelican/Pterodactyl game servers |
| Workstation VM | VM   | 48GB RAM  | 10.0.3.1 | 3001 | Gaming/Blender + GPU             |

### Old Server

Download disks, will join Proxmox cluster after migration.

### Future: Mini-PCs

16-32GB RAM each, Intel N100/N305 recommended for QuickSync transcoding.

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     Proxmox Host (10.0.1.1)                  │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Storage LXC  │  │ NetBird VM   │  │ Wings VM     │       │
│  │ (10.0.1.2)   │  │ (10.0.1.4)   │  │ (10.0.1.6)   │       │
│  │ MergerFS     │  │ WireGuard    │  │ Docker +     │       │
│  │ NFS exports  │  │ Management   │  │ Game servers │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                              │
│  ┌─────────────────────────────┐  ┌──────────────────────┐  │
│  │ K3s VM (10.0.1.3)           │  │ Workstation VM       │  │
│  │ VMID: 1003                  │  │ (10.0.3.1)           │  │
│  │ Hydra cluster               │  │ VMID: 3001           │  │
│  │ ├── Traefik (ingress)       │  │ RTX 3070 passthrough │  │
│  │ ├── Authentik (identity)    │  │ Gaming / Blender     │  │
│  │ ├── Longhorn (storage)      │  │                      │  │
│  │ └── Services (media, apps)  │  │                      │  │
│  └─────────────────────────────┘  └──────────────────────┘  │
│                                                              │
│  Storage: /mnt/nvme (2TB) + /mnt/sda1-sdd1 (4x8TB HDDs)     │
└──────────────────────────────────────────────────────────────┘
```

## Related

- [Naming Scheme](./naming.md) — mythology-based naming conventions
- [Network Allocation](./network.md) — IP ranges, VMID scheme, topology
- [Key Decisions](./decisions.md) — rationale for major technical choices
- [Resilience nodes (roadmap)](../roadmaps/infrastructure/resilience-nodes.md) — hosted DR nodes (configs only, no Longhorn)
