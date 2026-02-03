---
title: Migration Plan
---

# Migration Plan

Phased migration from single-VM Docker Compose to multi-node K3s on Proxmox.

## Phases Overview

| Phase | Focus | Status |
|-------|-------|--------|
| [[#Phase 0|Phase 0]] | Pre-migration (free up drives) | Pending |
| [[#Phase 1|Phase 1]] | Foundation (Proxmox, K3s, storage) | Pending |
| [[#Phase 2|Phase 2]] | NFS storage for K3s | Pending |
| [[#Phase 3|Phase 3]] | Core infrastructure (Auth, Network) | Pending |
| [[#Phase 4|Phase 4]] | Service migrations | Pending |
| [[#Phase 4B|Phase 4B]] | Workstation VM | Pending |
| [[#Phase 5|Phase 5]] | Retire old server | Pending |
| [[#Phase 6|Phase 6]] | Mini-PCs | Pending |

---

## Phase 0

**Pre-Migration: Free Up Drives**

### 0.1 Set Up 2TB NVMe Mount

```ini
# /etc/systemd/system/mnt-nvme.mount
[Unit]
Description=2TB NVMe Data Drive

[Mount]
What=/dev/nvme1n1p1
Where=/mnt/nvme
Type=ext4
Options=defaults,noatime

[Install]
WantedBy=multi-user.target
```

```bash
mkfs.ext4 /dev/nvme1n1
mkdir -p /mnt/nvme
systemctl daemon-reload
systemctl enable --now mnt-nvme.mount
```

### 0.2 Directory Structure

```
/mnt/nvme/
├── databases/       # PostgreSQL, MariaDB data dirs
├── configs/         # Service configs
└── critical/        # Other mission-critical data
```

### 0.3 Migrate ZFS Mirror Data

1. `rsync -avP /path/to/zfs/data/ /mnt/nvme/`
2. Verify data integrity (checksums, spot checks)
3. `zpool destroy oldpool`
4. Wipe 2x8TB drives - now available for MergerFS

---

## Phase 1

**Foundation: Proxmox, Storage, K3s**

1. Configure Proxmox bridges (vmbr0 2.5GbE mgmt, vmbr1 10GbE K3s)
2. Mount HDDs and NVMe on host
3. Create Storage LXC with MergerFS + NFS
4. Create K3s VM
5. Install kube-vip (before K3s)
6. Install K3s with cluster-init
7. Configure LoadBalancer IP pool
8. Install Longhorn, cert-manager, ClusterIssuer

See: [[../infrastructure/storage|Storage LXC]], [[../infrastructure/kubernetes|Kubernetes]]

---

## Phase 2

**NFS Storage for K3s**

Create PersistentVolumes for:

| Source | Export | Contents |
|--------|--------|----------|
| Storage LXC (10.0.1.2) | /mnt/media | Media library |
| Storage LXC (10.0.1.2) | /mnt/nvme | Critical data |
| Old Server (10.0.1.8) | /mnt/downloads | Download staging |

---

## Phase 3

**Core Infrastructure**

1. Create Authentik LXC (10.0.1.3)
2. Create Netbird LXC (10.0.1.5)
3. Deploy Netbird exit nodes in K3s
4. Configure Netbird DNS
5. Deploy Cloudflare Workers (Janus)
6. Configure Traefik forward auth
7. Migrate Jellyfin (practice with SSO)

See: [[../infrastructure/authentik|Authentik]], [[../infrastructure/netbird|Netbird]], [[../services/janus|Janus]]

---

## Phase 4

**Service Migrations**

Order:
1. Nextcloud (critical)
2. Bitwarden (official Helm chart)
3. Plausible (analytics)
4. Media stack (Sonarr, Radarr, SABnzbd, qBittorrent)
5. Pelican (game servers)
6. Forgejo (git hosting)

For each:
1. Create namespace + Longhorn PVC
2. Customize Helm values or write manifests
3. Backup/restore data from old Docker Compose
4. Create IngressRoute, update DNS
5. Decommission old container

---

## Phase 4B

**Workstation VM**

- 24 vCPUs, 48GB RAM
- RTX 3070 passthrough
- vmbr0 (2.5GbE)
- Power button toggle via acpid

Total 36 vCPUs on 32 threads = mild overcommit (fine)

---

## Phase 5

**Retire Old Server**

1. All services migrated and verified
2. Install Proxmox, `pvecm add <workstation-ip>`
3. Restore download disk NFS (LXC or VM)
4. Add K3s server node via VIP

---

## Phase 6

**Mini-PCs**

- Join as server (control plane) or agent (workloads only)
- Dedicate one to Jellyfin with Intel QuickSync
- Old server can stay as K3s server

---

## Future Tasks

| Task | Trigger |
|------|---------|
| NVMe to RAIDZ1 | When 2 more NVMe drives added |
| HDD upgrades | Gradually replace 8TB with 22TB |
