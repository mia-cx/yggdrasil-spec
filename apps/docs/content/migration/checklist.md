---
title: Migration Checklist
---

# Migration Checklist

Step-by-step checklist for the migration.

## Phase 0: Pre-Migration

- [ ] Format NVMe data drive (ext4)
- [ ] Create systemd mount unit for /mnt/nvme
- [ ] Create directory structure (databases, configs, critical)
- [ ] rsync ZFS data to /mnt/nvme
- [ ] Verify data integrity
- [ ] Destroy ZFS pool
- [ ] Wipe freed drives for MergerFS

## Phase 1: Foundation

### Network
- [ ] Configure vmbr0 (2.5GbE management)
- [ ] Configure vmbr1 (10GbE K3s)

### Host Storage
- [ ] Add HDD mount entries to /etc/fstab
- [ ] Create mount directories
- [ ] Mount all drives, verify with `df -h`

### Storage LXC
- [ ] Create Debian 12 LXC (10.0.1.2)
- [ ] Add bind mounts to LXC config
- [ ] Install nfs-kernel-server, mergerfs
- [ ] Configure MergerFS in LXC fstab
- [ ] Configure NFS exports
- [ ] Enable and start NFS server
- [ ] Test NFS mounts from another machine

### K3s VM
- [ ] Create VM (12 vCPU, 16GB RAM, 100GB disk)
- [ ] Install Ubuntu 22.04 or Debian 12
- [ ] Set static IP 10.0.1.4

### kube-vip
- [ ] Create manifests directory
- [ ] Download RBAC manifest
- [ ] Create DaemonSet manifest (ARP mode)
- [ ] Set VIP to 10.0.128.1

### K3s
- [ ] Install K3s with --cluster-init
- [ ] Verify nodes: `kubectl get nodes`
- [ ] Verify VIP: `ping 10.0.128.1`

### Components
- [ ] Create LoadBalancer IP pool configmap
- [ ] Copy kubeconfig, update server address
- [ ] Install Longhorn
- [ ] Install cert-manager
- [ ] Create Cloudflare API token secret
- [ ] Create ClusterIssuer
- [ ] Create wildcard Certificate

## Phase 2: NFS Storage

- [ ] Create media-nfs PersistentVolume
- [ ] Create critical-nfs PersistentVolume
- [ ] Create downloads-nfs PersistentVolume
- [ ] Create corresponding PVCs
- [ ] Test mounting from a pod

## Phase 3: Core Infrastructure

### Authentik LXC
- [ ] Create Debian 12 LXC (10.0.1.3)
- [ ] Install Docker and docker-compose
- [ ] Download Authentik docker-compose.yml
- [ ] Generate secrets (.env file)
- [ ] Start Authentik
- [ ] Initial setup (admin password)
- [ ] Create OIDC applications (Netbird, Jellyfin, etc.)
- [ ] Create groups (media-users, media-admin, etc.)

### Netbird LXC
- [ ] Create Debian 12 LXC (10.0.1.5)
- [ ] Install Docker and docker-compose
- [ ] Configure with Authentik OIDC
- [ ] Start Netbird management
- [ ] Test authentication

### Netbird Exit Nodes
- [ ] Create exit node DaemonSet manifest
- [ ] Deploy to K3s
- [ ] Verify connection to management

### DNS
- [ ] Configure Netbird DNS nameserver group
- [ ] Set up internal DNS (CoreDNS/AdGuard)
- [ ] Add internal DNS records
- [ ] Test split-horizon resolution

### Cloudflare Workers (Janus)
- [ ] Create Cloudflare Worker
- [ ] Add service definitions
- [ ] Configure route *.yggdrasil.mia.cx
- [ ] Deploy
- [ ] Test landing pages

### Traefik
- [ ] Create Authentik forward auth middleware
- [ ] Test protected route

### Jellyfin
- [ ] Deploy Jellyfin to K3s
- [ ] Mount media NFS volume
- [ ] Install SSO plugin
- [ ] Configure Authentik OIDC
- [ ] Test SSO login
- [ ] Test group-based permissions

## Phase 4: Service Migrations

### Nextcloud
- [ ] Backup data from old instance
- [ ] Deploy to K3s
- [ ] Configure OIDC
- [ ] Restore data
- [ ] Update DNS
- [ ] Decommission old

### Bitwarden
- [ ] Deploy official Helm chart
- [ ] Configure rawManifests for IngressRoute
- [ ] Migrate data
- [ ] Test functionality
- [ ] Update DNS
- [ ] Decommission old

### Plausible
- [ ] Deploy to K3s
- [ ] Migrate data
- [ ] Update DNS
- [ ] Decommission old

### Media Stack
- [ ] Deploy Sonarr
- [ ] Deploy Radarr
- [ ] Deploy SABnzbd
- [ ] Deploy qBittorrent
- [ ] Configure NFS mounts (downloads + media)
- [ ] Migrate configs
- [ ] Test functionality
- [ ] Update DNS
- [ ] Decommission old

### Pelican / Wings
- [ ] Create Wings VM (10.0.1.6, VMID 1006)
- [ ] Install Docker on Wings VM
- [ ] Install Wings daemon
- [ ] Deploy Pelican Panel to K3s
- [ ] Configure Panel → Wings connection
- [ ] Configure router port forwards for game servers
- [ ] Migrate game servers
- [ ] Test functionality

### Forgejo
- [ ] Deploy Forgejo
- [ ] Configure OIDC
- [ ] Set up GitHub push mirror
- [ ] Migrate repos
- [ ] Update DNS

## Phase 4B: Workstation VM

- [ ] Create VM (24 vCPU, 48GB RAM)
- [ ] Configure GPU passthrough
- [ ] Install OS
- [ ] Set up acpid power button toggle

## Phase 5: Retire Old Server

- [ ] Verify all services migrated
- [ ] Final backup of old server
- [ ] Wipe and install Proxmox
- [ ] Join Proxmox cluster: `pvecm add`
- [ ] Set up download disk NFS
- [ ] Add K3s server node via VIP
- [ ] Verify cluster health

## Phase 6: Mini-PCs

- [ ] Install Proxmox on first mini-PC
- [ ] Create K3s VM
- [ ] Join K3s cluster
- [ ] Configure Intel QuickSync for Jellyfin
- [ ] Move Jellyfin to mini-PC node
- [ ] Repeat for additional mini-PCs
