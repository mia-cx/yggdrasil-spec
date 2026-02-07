---
title: Migration
---

# Migration

Phased migration from single-VM Docker Compose to multi-node K3s on Proxmox.

## Phases Overview

| Phase                                    | Focus                               | Status  |
| ---------------------------------------- | ----------------------------------- | ------- |
| [Phase 0](#phase-0--pre-migration)       | Pre-migration (free up drives)      | Pending |
| [Phase 1](#phase-1--foundation)          | Foundation (Proxmox, K3s, storage)  | Pending |
| [Phase 2](#phase-2--nfs-storage)         | NFS storage for K3s                 | Pending |
| [Phase 3](#phase-3--core-infrastructure) | Core infrastructure (Auth, Network) | Pending |
| [Phase 4](#phase-4--service-migrations)  | Service migrations                  | Pending |
| [Phase 4B](#phase-4b--workstation-vm)    | Workstation VM                      | Pending |
| [Phase 5](#phase-5--retire-old-server)   | Retire old server                   | Pending |
| [Phase 6](#phase-6--mini-pcs)            | Mini-PCs                            | Pending |

---

## Phase 0 -- Pre-Migration

Free up drives by migrating ZFS data to the NVMe.

### Steps

1. Format NVMe data drive:

```bash
mkfs.ext4 /dev/nvme1n1
mkdir -p /mnt/nvme
```

2. Create systemd mount:

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
systemctl daemon-reload
systemctl enable --now mnt-nvme.mount
```

3. Directory structure:

```
/mnt/nvme/
├── databases/       # PostgreSQL, MariaDB data dirs
├── configs/         # Service configs
└── critical/        # Other mission-critical data
```

4. Migrate data:

```bash
rsync -avP /path/to/zfs/data/ /mnt/nvme/
# Verify data integrity (checksums, spot checks)
zpool destroy oldpool
# Wipe 2x8TB drives -- now available for MergerFS
```

### Checklist

- [x] Format NVMe data drive (ext4)
- [x] Create fstab mount unit for /mnt/nvme
- [x] rsync ZFS data to /mnt/nvme
- [ ] Verify data integrity
- [ ] Destroy ZFS pool
- [ ] Wipe freed drives for MergerFS

---

## Phase 1 -- Foundation

Proxmox networking, host storage, Storage LXC, and the K3s cluster.

### Steps

1. Configure Proxmox bridges (vmbr0 2.5GbE mgmt, vmbr1 10GbE K3s)
2. Mount HDDs and NVMe on host
3. Create Storage LXC with MergerFS + NFS
4. Create K3s VM
5. Install kube-vip (before K3s)
6. Install K3s with cluster-init
7. Configure LoadBalancer IP pool
8. Install Longhorn, cert-manager, ClusterIssuer

See: [Storage LXC](../infrastructure/storage.md), [Kubernetes](../infrastructure/kubernetes.md)

### Checklist

**Network**

- [ ] Configure vmbr0 (2.5GbE management)
- [ ] Configure vmbr1 (10GbE K3s)

**Host Storage**

- [ ] Add HDD mount entries to /etc/fstab
- [ ] Create mount directories
- [ ] Mount all drives, verify with `df -h`

**Storage LXC**

- [ ] Create Debian 12 LXC (10.0.1.2)
- [ ] Add bind mounts to LXC config
- [ ] Install nfs-kernel-server, mergerfs
- [ ] Configure MergerFS in LXC fstab
- [ ] Configure NFS exports
- [ ] Enable and start NFS server
- [ ] Test NFS mounts from another machine

**K3s VM**

- [ ] Create VM (12 vCPU, 16GB RAM, 100GB disk)
- [ ] Install Debian 12
- [ ] Set static IP 10.0.1.3

**kube-vip**

- [ ] Create manifests directory
- [ ] Download RBAC manifest
- [ ] Create DaemonSet manifest (ARP mode)
- [ ] Set VIP to 10.0.128.1

**K3s**

- [ ] Install K3s with --cluster-init
- [ ] Verify nodes: `kubectl get nodes`
- [ ] Verify VIP: `ping 10.0.128.1`

**Components**

- [ ] Create LoadBalancer IP pool configmap
- [ ] Copy kubeconfig, update server address
- [ ] Install Longhorn
- [ ] Install cert-manager
- [ ] Create Cloudflare API token secret
- [ ] Create ClusterIssuer
- [ ] Create wildcard Certificate

---

## Phase 2 -- NFS Storage

Create PersistentVolumes for cluster-wide NFS access.

| Source                 | Export         | Contents         |
| ---------------------- | -------------- | ---------------- |
| Storage LXC (10.0.1.2) | /mnt/media     | Media library    |
| Storage LXC (10.0.1.2) | /mnt/nvme      | Critical data    |
| Old Server (10.0.1.8)  | /mnt/downloads | Download staging |

### Checklist

- [ ] Create media-nfs PersistentVolume
- [ ] Create nvme-nfs PersistentVolume
- [ ] Create downloads-nfs PersistentVolume
- [ ] Create corresponding PVCs
- [ ] Test mounting from a pod

---

## Phase 3 -- Core Infrastructure

Identity, overlay network, DNS, and ingress.

### Steps

1. Create Authentik LXC (10.0.1.3)
2. Create Netbird LXC (10.0.1.5)
3. Deploy Netbird exit nodes in K3s
4. Configure Netbird DNS
5. Deploy Cloudflare Workers (Janus)
6. Configure Traefik forward auth
7. Migrate Jellyfin (practice with SSO)

See: [Authentik](../infrastructure/authentik.md), [Netbird](../infrastructure/netbird.md), [Janus](../services/janus.md)

### Checklist

**Authentik LXC**

- [ ] Create Debian 12 LXC (10.0.1.3)
- [ ] Install Docker and docker-compose
- [ ] Download Authentik docker-compose.yml
- [ ] Generate secrets (.env file)
- [ ] Start Authentik
- [ ] Initial setup (admin password)
- [ ] Create OIDC applications (Netbird, Jellyfin, etc.)
- [ ] Create groups (media-users, media-admin, etc.)

**Netbird LXC**

- [ ] Create Debian 12 LXC (10.0.1.5)
- [ ] Install Docker and docker-compose
- [ ] Configure with Authentik OIDC
- [ ] Start Netbird management
- [ ] Test authentication

**Netbird Exit Nodes**

- [ ] Create exit node DaemonSet manifest
- [ ] Deploy to K3s
- [ ] Verify connection to management

**DNS**

- [ ] Configure Netbird DNS nameserver group
- [ ] Set up internal DNS (CoreDNS/AdGuard)
- [ ] Add internal DNS records
- [ ] Test split-horizon resolution

**Cloudflare Workers (Janus)**

- [ ] Create Cloudflare Worker
- [ ] Add service definitions
- [ ] Configure route \*.yggdrasil.mia.cx
- [ ] Deploy
- [ ] Test landing pages

**Traefik**

- [ ] Create Authentik forward auth middleware
- [ ] Test protected route

**Jellyfin**

- [ ] Deploy Jellyfin to K3s
- [ ] Mount media NFS volume
- [ ] Install SSO plugin
- [ ] Configure Authentik OIDC
- [ ] Test SSO login
- [ ] Test group-based permissions

---

## Phase 4 -- Service Migrations

Migrate each service from Docker Compose to K3s.

### Migration pattern

For each service:

1. Create namespace + Longhorn PVC
2. Customize Helm values or write manifests
3. Backup/restore data from old Docker Compose
4. Create IngressRoute, update DNS
5. Decommission old container

### Checklist

**Nextcloud**

- [ ] Backup data from old instance
- [ ] Deploy to K3s
- [ ] Configure OIDC
- [ ] Restore data
- [ ] Update DNS
- [ ] Decommission old

**Vaultwarden**

- [ ] Deploy official Helm chart
- [ ] Configure rawManifests for IngressRoute
- [ ] Migrate data
- [ ] Test functionality
- [ ] Update DNS
- [ ] Decommission old

**Media Stack**

- [ ] Deploy Sonarr, Radarr, Lidarr, Prowlarr
- [ ] Deploy SABnzbd, qBittorrent
- [ ] Deploy FlareSolverr, Privoxy, Prefetcharr, Tdarr
- [ ] Configure NFS mounts (downloads + media)
- [ ] Migrate configs
- [ ] Test functionality
- [ ] Update DNS
- [ ] Decommission old

**Pelican / Wings**

- [ ] Create Wings VM (10.0.1.6, VMID 1006)
- [ ] Install Docker on Wings VM
- [ ] Install Wings daemon
- [ ] Deploy Pelican Panel to K3s
- [ ] Configure Panel → Wings connection
- [ ] Configure router port forwards for game servers
- [ ] Migrate game servers
- [ ] Test functionality

**Forgejo**

- [ ] Deploy Forgejo
- [ ] Configure OIDC
- [ ] Set up GitHub push mirror
- [ ] Migrate repos
- [ ] Update DNS

---

## Phase 4B -- Workstation VM

- 24 vCPUs, 48GB RAM
- RTX 3070 passthrough
- vmbr0 (2.5GbE)
- Power button toggle via acpid

Total 36 vCPUs on 32 threads = mild overcommit (acceptable).

### Checklist

- [ ] Create VM (24 vCPU, 48GB RAM)
- [ ] Configure GPU passthrough
- [ ] Install OS
- [ ] Set up acpid power button toggle

---

## Phase 5 -- Retire Old Server

1. All services migrated and verified
2. Install Proxmox, `pvecm add <workstation-ip>`
3. Restore download disk NFS (LXC or VM)
4. Add K3s server node via VIP

### Checklist

- [ ] Verify all services migrated
- [ ] Final backup of old server
- [ ] Wipe and install Proxmox
- [ ] Join Proxmox cluster: `pvecm add`
- [ ] Set up download disk NFS
- [ ] Add K3s server node via VIP
- [ ] Verify cluster health

---

## Phase 6 -- Mini-PCs

- Join as server (control plane) or agent (workloads only)
- Dedicate one to Jellyfin with Intel QuickSync
- Old server can stay as K3s server

### Checklist

- [ ] Install Proxmox on first mini-PC
- [ ] Create K3s VM
- [ ] Join K3s cluster
- [ ] Configure Intel QuickSync for Jellyfin
- [ ] Move Jellyfin to mini-PC node
- [ ] Repeat for additional mini-PCs

---

## Future Tasks

| Task           | Trigger                         |
| -------------- | ------------------------------- |
| NVMe to RAIDZ1 | When 2 more NVMe drives added   |
| HDD upgrades   | Gradually replace 8TB with 22TB |
