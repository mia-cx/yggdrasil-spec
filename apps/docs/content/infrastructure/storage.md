---
title: Storage LXC
---

# Storage LXC

Lightweight container providing MergerFS pooling and NFS exports for the cluster.

## Overview

| Property | Value |
|----------|-------|
| IP | 10.0.1.2 |
| Template | debian-12-standard |
| vCPUs | 1-2 |
| RAM | 1GB |
| Disk | 8GB root |

## Host Mounts (Proxmox)

```bash
# /etc/fstab on Proxmox host
/dev/nvme1n1p1  /mnt/nvme   ext4  defaults,noatime  0 2
/dev/sda1       /mnt/disk1  ext4  defaults,noatime  0 2
/dev/sdb1       /mnt/disk2  ext4  defaults,noatime  0 2
/dev/sdc1       /mnt/disk3  ext4  defaults,noatime  0 2
/dev/sdd1       /mnt/disk4  ext4  defaults,noatime  0 2
```

## LXC Config

Add bind mounts in `/etc/pve/lxc/<id>.conf`:

```
mp0: /mnt/nvme,mp=/mnt/nvme
mp1: /mnt/disk1,mp=/mnt/disk1
mp2: /mnt/disk2,mp=/mnt/disk2
mp3: /mnt/disk3,mp=/mnt/disk3
mp4: /mnt/disk4,mp=/mnt/disk4
```

## Inside LXC

### Install packages

```bash
apt update && apt install -y nfs-kernel-server mergerfs
```

### MergerFS fstab

```bash
# /etc/fstab (inside LXC)
/mnt/disk1:/mnt/disk2:/mnt/disk3:/mnt/disk4  /mnt/media  fuse.mergerfs  defaults,allow_other,use_ino,cache.files=partial,dropcacheonclose=true,category.create=mfs  0 0
```

```bash
mkdir -p /mnt/media
mount -a
```

### NFS exports

```bash
# /etc/exports
/mnt/nvme   10.0.0.0/16(rw,sync,no_subtree_check,no_root_squash)
/mnt/media  10.0.0.0/16(rw,sync,no_subtree_check,no_root_squash)
```

```bash
exportfs -ra
systemctl enable --now nfs-server
```

## Architecture Diagram

```
Proxmox Host
├── /mnt/nvme (ext4, future ZFS)
├── /mnt/disk1-4 (HDDs)
│
└── Storage LXC (10.0.1.2)
    ├── Bind: /mnt/nvme ──────▶ NFS export
    ├── Bind: /mnt/disk1-4
    │       │
    │       ▼
    │   MergerFS /mnt/media ──▶ NFS export
    │
    └── K3s accesses both via NFS PVs
```

## NFS Exports Summary

| Export | Source | Contents |
|--------|--------|----------|
| /mnt/nvme | NVMe SSD | Databases, configs, critical data |
| /mnt/media | MergerFS (4x8TB) | Media library |

## Future: ZFS Migration

When migrating NVMe to ZFS:
1. Backup `/mnt/nvme` to MergerFS
2. Create RAIDZ1 pool on NVMe drives
3. Set mountpoint: `zfs set mountpoint=/mnt/nvme tank`
4. Restore data

LXC sees same bind mount path - no NFS changes needed.
