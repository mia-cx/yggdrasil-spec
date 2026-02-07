---
title: Storage LXC
---

# Storage LXC

## Overview

| Property | Value              |
| -------- | ------------------ |
| Type     | LXC (privileged)   |
| IP       | 10.0.1.2           |
| VMID     | 1002               |
| Template | debian-13-standard |
| vCPUs    | 1-2                |
| RAM      | 1GB                |
| Disk     | 8GB root           |

Lightweight container providing MergerFS pooling and NFS exports for the cluster. Four 8TB HDDs are merged into a single `/mnt/media` pool; the NVMe is exported separately for critical data.

## Prerequisites

- Proxmox host with disks available (`/dev/sda1`-`/dev/sdd1`, `/dev/nvme1n1p1`)
- Network configured (static IP `10.0.1.2/16`)

## Setup

### Create the Container

1. Proxmox UI → Create CT
2. Use `debian-13-standard` template
3. Set hostname: `storage`
4. 8GB root disk, 1-2 vCPUs, 1GB RAM
5. Network: static IP `10.0.1.2/16`, gateway `10.0.0.1`

### FUSE Passthrough

MergerFS requires FUSE inside the container. Add to `/etc/pve/lxc/1002.conf` on the Proxmox host:

```
lxc.cgroup2.devices.allow: c 10:229 rwm
lxc.mount.entry: /dev/fuse dev/fuse none bind,create=file 0 0
```

Without this, `mount -t fuse.mergerfs` will fail inside the LXC.

Optionally enable nesting for nested mount namespaces:

```
features: nesting=1,fuse=1
```

### Host Disk Preparation

If disks previously belonged to a ZFS pool, wipe residual metadata before formatting:

```bash
# Clear old metadata
wipefs -a /dev/sda1
wipefs -a /dev/sdb1
wipefs -a /dev/sdc1
wipefs -a /dev/sdd1

# Format as ext4
mkfs.ext4 /dev/sda1
mkfs.ext4 /dev/sdb1
mkfs.ext4 /dev/sdc1
mkfs.ext4 /dev/sdd1
```

Create mount points and add to `/etc/fstab` on the Proxmox host:

```bash
mkdir -p /mnt/nvme /mnt/sda1 /mnt/sdb1 /mnt/sdc1 /mnt/sdd1
```

```bash
# /etc/fstab on Proxmox host
/dev/nvme1n1p1  /mnt/nvme   ext4  defaults,noatime  0 2
/dev/sda1       /mnt/sda1   ext4  defaults,noatime  0 2
/dev/sdb1       /mnt/sdb1   ext4  defaults,noatime  0 2
/dev/sdc1       /mnt/sdc1   ext4  defaults,noatime  0 2
/dev/sdd1       /mnt/sdd1   ext4  defaults,noatime  0 2
```

```bash
mount -a
```

### LXC Bind Mounts

Add bind mounts in `/etc/pve/lxc/1002.conf` so the LXC can access host disks:

```
mp0: /mnt/nvme,mp=/mnt/nvme
mp1: /mnt/sda1,mp=/mnt/sda1
mp2: /mnt/sdb1,mp=/mnt/sdb1
mp3: /mnt/sdc1,mp=/mnt/sdc1
mp4: /mnt/sdd1,mp=/mnt/sdd1
```

Restart the container after changing the config:

```bash
pct stop 1002
pct start 1002
```

### Inside LXC

Enter the container:

```bash
pct enter 1002   # from Proxmox host
ssh root@10.0.1.2  # or via SSH
```

Install packages:

```bash
apt update && apt install -y nfs-kernel-server mergerfs
```

Verify FUSE is available:

```bash
ls -l /dev/fuse
```

If missing, the FUSE passthrough config wasn't applied -- double-check `/etc/pve/lxc/1002.conf` and restart the container.

## Configuration

### MergerFS Pool

```bash
mkdir -p /mnt/media
```

Add the MergerFS entry to `/etc/fstab` (inside LXC):

```bash
/mnt/sda1:/mnt/sdb1:/mnt/sdc1:/mnt/sdd1  /mnt/media  fuse.mergerfs  defaults,allow_other,use_ino,cache.files=partial,dropcacheonclose=true,category.create=mfs  0 0
```

```bash
mount -a
df -h /mnt/media
```

### NFS Exports

```bash
# /etc/exports
/mnt/nvme   10.0.0.0/16(rw,sync,no_subtree_check,no_root_squash)
/mnt/media  10.0.0.0/16(rw,sync,no_subtree_check,no_root_squash,fsid=1)
```

> **Note:** MergerFS is a FUSE filesystem, so NFS cannot auto-assign a filesystem ID. The explicit `fsid=1` is required for the export to work.

```bash
exportfs -ra
systemctl enable --now nfs-server
```

## Architecture

```
Proxmox Host
├── /mnt/nvme (ext4, future ZFS)
├── /mnt/sda1-sdd1 (HDDs)
│
└── Storage LXC (10.0.1.2, privileged)
    ├── /dev/fuse passthrough (for MergerFS)
    ├── Bind: /mnt/nvme ──────────▶ NFS export
    ├── Bind: /mnt/sda1-sdd1
    │       │
    │       ▼
    │   MergerFS /mnt/media ──────▶ NFS export
    │
    └── K3s accesses both via NFS PVs
```

### NFS Exports Summary

| Export       | Source           | Contents                          |
| ------------ | ---------------- | --------------------------------- |
| `/mnt/nvme`  | NVMe SSD         | Databases, configs, critical data |
| `/mnt/media` | MergerFS (4x8TB) | Media library (~29Ti usable)      |

## Verification

```bash
# From another machine on the network
showmount -e 10.0.1.2

# Check mounts inside LXC
df -h /mnt/media /mnt/nvme

# Check NFS exports
exportfs -v
```

## Future: ZFS Migration

When migrating NVMe to ZFS:

1. Backup `/mnt/nvme` to MergerFS
2. Create RAIDZ1 pool on NVMe drives
3. Set mountpoint: `zfs set mountpoint=/mnt/nvme tank`
4. Restore data

LXC sees same bind mount path -- no NFS changes needed.
