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

LXCs have their own root password and users (they do **not** share the Proxmox host’s). To SSH in with a key, add your public key to the container’s `/root/.ssh/authorized_keys` after creation — e.g. from the host: `pct enter 1002`, then create `~/.ssh` and `authorized_keys`. See [Runbooks — Proxmox](../../operations/runbooks.md#proxmox) for the exact commands.

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

## NFS over Netbird (cross-site)

NFS **can** be made available over the Netbird overlay so Tdarr nodes (or other pods) on different sites (e.g. Elysium, Arcadia) can mount the same media and transcode.

**How:** Ensure the NFS server (Storage LXC at 10.0.1.2, or the host that serves NFS) is a Netbird peer so it has an overlay IP and is routable from other sites. Configure Netbird ACLs so K3s nodes at every site can reach that peer. PVs today use LAN IPs (10.0.1.x); if Netbird routes Olympus LAN (e.g. 10.0.0.0/16) to the Olympus Netbird peer, remote nodes can mount using the same PV server address. Alternatively, run NFS on a host that has only an overlay IP and point the PVs at that overlay IP (requires NFS listen on the overlay interface).

**Caveat:** NFS is stateful and sensitive to latency and packet loss. Over a WAN link (even through Netbird) you get higher RTT and possible jitter. For transcoding—mostly sequential read of a large file and write of the result—throughput is often acceptable on a solid link (e.g. 50–100+ Mbps, low loss). If transcodes are slow or NFS locks up, either (1) run Tdarr nodes only at the site that has the NFS server, or (2) sync media to the remote site (e.g. rclone) and run Tdarr there on local storage.

**Recommendation:** Try NFS over Netbird first. You don’t need to move media to object storage or another WAN-oriented system unless you hit real limits or reliability issues.

### Why not Longhorn for media?

Longhorn does **not** ingest or “hook into” external storage. It provisions **block volumes from disks attached to K3s nodes** — it has no backend driver for NFS, NAS, or your Storage LXC. To put 29 Ti of media in Longhorn you’d need that capacity as raw block devices on the nodes themselves; mini-PCs and K3s VMs don’t have it, and replication would multiply the requirement. Longhorn is the right tool for **small, replicated state** (databases, configs) on node-local disks.

**Pod-to-pod over WAN:** Longhorn replicates blocks between nodes; if a pod on site B reads a volume whose replica lives on site A, I/O goes over the network. Longhorn is built for **LAN / low-latency** links. Over WAN, sync replication adds latency and failure modes — which is why [resilience nodes](../roadmaps/infrastructure/resilience-nodes.md) explicitly disable Longhorn scheduling on remote nodes. So Longhorn is robust for pod↔pod **on a LAN**; it is not a substitute for NFS or sync when you need large, cross-site media.

### Replication: two-layer redundancy

You want **at least two copies of every chunk across nodes** so one node can go offline without data loss or loss of availability. That’s a second layer on top of **ZFS RAID-Z1 per node** (first layer: one drive failure per vdev).

| Option                      | Replication model                                                                                                                  | 2+ copies across nodes?        | One node down = no data loss, still available?                                          |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ | --------------------------------------------------------------------------------------- |
| **Ceph**                    | Replica count (e.g. 2 or 3) or erasure coding. CRUSH places replicas on different failure domains (node/rack).                     | Yes                            | Yes. Set replica count ≥ 2 and failure domain = node.                                   |
| **GlusterFS**               | Replicated volume: each file replicated to N bricks on different nodes.                                                            | Yes (replica 2 or 3)           | Yes. One node down → other replica(s) serve.                                            |
| **JuiceFS + MinIO**         | Data lives in the object store. Replication is **MinIO’s job**: distributed MinIO with erasure coding or replication across nodes. | Yes (via MinIO replication/EC) | Yes, if MinIO is configured for ≥2 copies or EC across nodes.                           |
| **SeaweedFS**               | Volume-level replication: each volume has N replicas on different volume servers.                                                  | Yes (e.g. replication 2)       | Yes. One node down → other replica(s).                                                  |
| **Longhorn**                | Block volume replicas (2 or 3) on different nodes.                                                                                 | Yes (block vols only)          | Yes. Not a global media FS.                                                             |
| **Sync (rclone/Syncthing)** | Full copy per site; no chunk-level replication.                                                                                    | Yes (full copy per site)       | Yes for “one site down” if you have 2+ sites. Different model than cluster replication. |

**CRUSH hierarchy mapping (if you use Ceph):** Ceph’s [CRUSH map](https://docs.ceph.com/en/latest/rados/operations/crush-map/#types-and-buckets) has built-in bucket types you can align with your layout. For **site → room → rack → machine → disks** use:

| Your level   | CRUSH type                         | Notes                                                |
| ------------ | ---------------------------------- | ---------------------------------------------------- |
| Site         | `datacenter` or `zone` or `region` | One of these; e.g. `datacenter=olympus`.             |
| Room         | `room`                             | Optional.                                            |
| Rack         | `rack`                             |                                                      |
| Machine/node | `host`                             | OSDs are usually placed under `host` (one per node). |
| Disks        | `osd`                              | Leaves; one OSD per disk (or per LVM LV).            |

So: `root` → `datacenter` (site) → `room` (optional) → `rack` → `host` → `osd`. Rules then use failure domains like `type host` (replicas on different nodes) or `type datacenter` (replicas across sites).

**ZFS under Ceph:** You can run Ceph on top of ZFS (e.g. OSD backed by zvols); guides exist. The benefits (ARC, SLOG, L2ARC) matter most with mass NVMe when you need to push throughput beyond raw disk. If your network is 10GbE or slower (1.25 GB/s), the network is the bottleneck; NVMe already does 3.5-14 GB/s, so the extra ZFS layer doesn't buy much. For 10GbE-and-below homelab, raw/LVM under Ceph or ZFS per node with a different cluster layer (NFS, Gluster, JuiceFS, sync) is the simpler choice.

**Two-layer design:** Node-local ZFS RAID-Z1 protects against single-drive failure per node. Cluster-level replication (Ceph/Gluster/JuiceFS+MinIO/SeaweedFS) protects against node failure and keeps data available when one node is offline. Configure replica count (or erasure coding) so every chunk has at least 2 copies on different nodes (or different failure domains).

### Layer 3: site-level (one site offline)

If an **entire site** goes offline, other sites should still have the data. That means replicating or syncing **across sites**, not just across nodes at one site.

| Option                      | Cross-site strategy                                                                                                                                                                       | One site down = other sites have data?                                |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| **Ceph**                    | Stretch cluster (replicas across failure domains that are sites), or RBD/FS mirroring to a second cluster.                                                                                | Yes, if configured (replicas across sites or async mirror to site B). |
| **GlusterFS**               | Geo-replication: async (or sync) replicate a volume to a second cluster at another site.                                                                                                  | Yes.                                                                  |
| **JuiceFS + MinIO**         | Replicate MinIO buckets to a second MinIO cluster at another site (MinIO replication or external sync); or run MinIO per site and sync. JuiceFS metadata must be reachable or replicated. | Yes, with cross-site MinIO replication or bucket sync.                |
| **SeaweedFS**               | Replicate to another SeaweedFS cluster (cross-datacenter replication).                                                                                                                    | Yes.                                                                  |
| **Sync (rclone/Syncthing)** | Each site holds a full copy; sync changes between sites.                                                                                                                                  | Yes — this is the native model (N sites = N copies).                  |

So the full stack is: **ZFS RAID-Z1 (per node) → cluster replication across nodes (one node down) → cross-site replication or sync (one site down)**. All of the distributed options support some form of cross-site replication; sync is the simplest “every site has a copy” approach.

## Future: ZFS Migration

When migrating NVMe to ZFS:

1. Backup `/mnt/nvme` to MergerFS
2. Create RAIDZ1 pool on NVMe drives
3. Set mountpoint: `zfs set mountpoint=/mnt/nvme tank`
4. Restore data

LXC sees same bind mount path -- no NFS changes needed.
