---
name: Homelab K3s Migration
overview: Migrate from single-VM Docker Compose setup to a multi-node K3s cluster on Proxmox, with kube-vip for HA, cert-manager for Cloudflare DNS-01 certs, and phased service migration.
todos:
  - id: phase0-zfs
    content: Set up /mnt/nvme (ext4), copy ZFS mirror data there, dissolve zpool, free drives for MergerFS
    status: pending
  - id: phase1-network
    content: Configure Proxmox bridges (vmbr0 2.5GbE mgmt, vmbr1 10GbE K3s)
    status: pending
  - id: phase1-host-mounts
    content: Mount HDDs and NVMe on Proxmox host (fstab)
    status: pending
  - id: phase1-storage-lxc
    content: Create Storage LXC (Debian, MergerFS + NFS) with bind mounts from host
    status: pending
  - id: phase1-vm
    content: Create K3s VM (12 vCPUs, 16GB RAM, 100GB disk, 10GbE)
    status: pending
  - id: phase1-kubevip
    content: Install kube-vip manifests before K3s (VIP 10.0.128.1)
    status: pending
  - id: phase1-k3s
    content: Install K3s with --cluster-init and --tls-san for VIP
    status: pending
  - id: phase1-components
    content: Install Longhorn, cert-manager, Cloudflare ClusterIssuer
    status: pending
  - id: phase2-nfs
    content: Configure NFS PVs (media + critical from Storage LXC, downloads from old server)
    status: pending
  - id: phase3-authentik-lxc
    content: Create Authentik LXC (10.0.1.3) - IdP for SSO, independent of K3s
    status: pending
  - id: phase3-netbird-lxc
    content: Create Netbird LXC (10.0.1.5) - management server with Authentik OIDC
    status: pending
  - id: phase3-netbird-exit
    content: Deploy Netbird exit nodes as DaemonSet in K3s
    status: pending
  - id: phase3-netbird-dns
    content: Configure Netbird DNS for internal service resolution (*.yggdrasil.mia.cx)
    status: pending
  - id: phase3-cf-workers
    content: Deploy Cloudflare Workers for internal-only service landing pages
    status: pending
  - id: phase3-traefik
    content: Configure Traefik with Authentik forward auth middleware
    status: pending
  - id: phase3-jellyfin
    content: Migrate Jellyfin with SSO plugin (Authentik OIDC)
    status: pending
  - id: phase4-nextcloud
    content: Migrate Nextcloud (critical)
    status: pending
  - id: phase4-bitwarden
    content: Migrate Bitwarden via Helm with Traefik rawManifest
    status: pending
  - id: phase4-plausible
    content: Migrate Plausible analytics
    status: pending
  - id: phase4-arr
    content: Migrate media stack (Sonarr, Radarr, SABnzbd, qBittorrent)
    status: pending
  - id: phase4-pelican
    content: Set up Pelican (Pterodactyl fork) for game servers
    status: pending
  - id: phase4-forgejo
    content: Set up Forgejo with GitHub push mirror
    status: pending
  - id: phase4b-workstation
    content: Create Workstation VM (24 vCPUs, 48GB, RTX 3070 passthrough)
    status: pending
  - id: phase4b-power
    content: Configure power button to toggle Workstation VM
    status: pending
  - id: phase5-retire
    content: Wipe old server, install Proxmox, join cluster
    status: pending
  - id: phase5-k3s-node
    content: Add old server as K3s server node + NFS for downloads
    status: pending
  - id: phase6-minipcs
    content: Add mini-PC nodes (Intel QuickSync for Jellyfin)
    status: pending
  - id: future-raidz1
    content: "When 2 more NVMe: backup /mnt/nvme to MergerFS, create RAIDZ1 pool, restore (keep mountpoint or use /tank)"
    status: pending
  - id: future-hdd
    content: Gradually replace 8TB drives with 22TB in MergerFS
    status: pending
isProject: false
---

# Homelab K3s Migration Plan

## Hardware Overview

**Workstation (Primary Node):**

- Ryzen 9 7950x (16c/32t), 96GB DDR5-5200
- RTX 3070 (passthrough to Workstation VM)
- NVMe: Slot 1 boot, Slot 2 2TB data at `/mnt/nvme` (ext4 now, RAIDZ1 later), Slots 3-4 future
- 4x8TB HDDs at `/mnt/disk1-4` (MergerFS via LXC) upgrading to 22TB over time
- 2.5GbE + 10GbE NICs

**VMs/Containers:**

- **Storage LXC** (1GB RAM, VMID 1002): MergerFS + NFS exports
- **Authentik LXC** (1-2GB RAM, VMID 1003): Identity provider for SSO
- **K3s VM** (16GB RAM, VMID 1004): Kubernetes workloads + Netbird exit nodes
- **Netbird LXC** (512MB-1GB RAM, VMID 1005): Overlay network management
- **Wings VM** (4-8GB RAM, VMID 1006): Pelican/Pterodactyl game servers (Docker)
- **Workstation VM** (48GB RAM, VMID 3001, IP 10.0.3.1): Gaming/Blender with GPU passthrough

**Old Server:** Download disks, will join Proxmox cluster after migration

**Future Mini-PCs:** 16-32GB RAM, consider Intel N100/N305 for QuickSync

---

## Naming Scheme (Mythology Theme)

**Hierarchy:**

```
Yggdrasil (world tree - entire infrastructure)
├── Olympus (your home - primary site)
│   ├── Athena (workstation host/VM)
│   ├── Hydra (K3s cluster)
│   └── ...
├── Elysium (mom's site - future)
├── Arcadia (dad's site - future)
└── Hera (WiFi SSIDs - spans all sites)
```

**Current Names:**

| Entity | Name | Mythology | Reason |

|--------|------|-----------|--------|

| Overall infrastructure | **Yggdrasil** | Norse | World tree connecting all realms |

| Your home site | **Olympus** | Greek | Primary location, seat of power |

| WiFi SSIDs | **Hera** | Greek | Marriage - "marries" devices |

| Home LAN | **Hestia** | Greek | Hearth, home |

| K3s cluster | **Hydra** | Greek | Multi-headed, regenerates |

| Workstation | **Athena** | Greek | Wisdom, crafts |

| Storage LXC | TBD | Greek | Mnemosyne? (memory) |

| Old server | TBD | Greek | Hephaestus? (forge) |

**Domain:** `yggdrasil.mia.cx` (services: `*.yggdrasil.mia.cx`)

---

## Your Network Allocation

```
Range             Purpose
10.0.0.0/24       Networking gear (router, switches)
10.0.1.0/24       Server hardware (see breakdown below)
10.0.2.0/24       IoT devices
10.0.3.0/24       Trusted LAN clients
10.0.4.0/24       Trusted WLAN clients
10.0.5.0/24       HiFi/theater LAN
10.0.6.0/24       HiFi/theater WLAN
10.0.15.0/24      Guest WLAN
10.0.128.0/17     Reserved for Kubernetes VIPs
```

**Server Hardware (10.0.1.0/24):**

```
10.0.1.1-7        Workstation (server infra)
├── 10.0.1.1      Proxmox host
├── 10.0.1.2      Storage LXC (NFS)         VMID: 1002
├── 10.0.1.3      Authentik LXC (IdP)       VMID: 1003
├── 10.0.1.4      K3s VM                    VMID: 1004
├── 10.0.1.5      Netbird LXC (management)  VMID: 1005
├── 10.0.1.6      Wings VM (game servers)   VMID: 1006
└── 10.0.1.7      spare

10.0.3.1          Workstation VM (client)   VMID: 3001

10.0.1.8-15       Old Server
├── 10.0.1.8      Proxmox host
├── 10.0.1.9      K3s VM                    VMID: 1009
└── 10.0.1.10-15  spare

10.0.1.16-127     Reserved (future powerful hardware)

10.0.1.128-255    Mini-PCs
├── 10.0.1.128    MPC-1 Proxmox host
├── 10.0.1.129    MPC-1 K3s VM              VMID: 1129
├── ...           MPC-1 reserved
├── 10.0.1.132    MPC-2 Proxmox host
├── 10.0.1.133    MPC-2 K3s VM              VMID: 1133
└── ...

VMID Pattern: (3rd_octet × 1000) + last_octet
```

**Kubernetes VIPs (10.0.128.0/24):**

- 10.0.128.1 - Control plane API
- 10.0.128.2 - Traefik/Ingress (router port-forward 80/443 here)
- 10.0.128.3-60 - Future LoadBalancer services

---

## Phase 0: Pre-Migration (Free Up Drives)

### 0.1 Set Up 2TB NVMe Mount

Create systemd mount unit for the NVMe data drive:

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
# Format and enable
mkfs.ext4 /dev/nvme1n1
mkdir -p /mnt/nvme
systemctl daemon-reload
systemctl enable --now mnt-nvme.mount
```

**Directory structure:**

```
/mnt/nvme/
├── databases/       # PostgreSQL, MariaDB data dirs
├── configs/         # Service configs
└── critical/        # Other mission-critical data
```

### 0.2 Migrate ZFS Mirror Data

1. `rsync -avP /path/to/zfs/data/ /mnt/nvme/`
2. Verify data integrity (checksums, spot checks)
3. `zpool destroy oldpool`
4. Wipe 2x8TB drives - now available for MergerFS

**Future RAIDZ1 migration:** When you have 3x NVMe, you can either:

- Set ZFS mountpoint to keep same path: `zfs set mountpoint=/mnt/nvme tank`
- Or use default `/tank` and update configs

---

## Phase 1: Foundation

### 1.1 Network Configuration

- **vmbr0** (2.5GbE): Proxmox management, Workstation VM
- **vmbr1** (10GbE): K3s VM, high-speed storage

### 1.2 Host Storage Mounts

Mount disks on Proxmox host (fstab for simple local mounts):

```bash
# /etc/fstab on Proxmox host
/dev/nvme1n1p1  /mnt/nvme   ext4  defaults,noatime  0 2
/dev/sda1       /mnt/disk1  ext4  defaults,noatime  0 2
/dev/sdb1       /mnt/disk2  ext4  defaults,noatime  0 2
/dev/sdc1       /mnt/disk3  ext4  defaults,noatime  0 2
/dev/sdd1       /mnt/disk4  ext4  defaults,noatime  0 2
```
```bash
mkdir -p /mnt/{nvme,disk1,disk2,disk3,disk4}
mount -a
```

### 1.3 Storage LXC Setup

**Create LXC in Proxmox:**

- Template: `debian-12-standard`
- 1-2 vCPUs, 1GB RAM
- 8GB root disk
- Network: vmbr0, static IP: 10.0.1.2

**Add bind mounts to LXC config** (`/etc/pve/lxc/<id>.conf`):

```
mp0: /mnt/nvme,mp=/mnt/nvme
mp1: /mnt/disk1,mp=/mnt/disk1
mp2: /mnt/disk2,mp=/mnt/disk2
mp3: /mnt/disk3,mp=/mnt/disk3
mp4: /mnt/disk4,mp=/mnt/disk4
```

**Inside LXC - install packages:**

```bash
apt update && apt install -y nfs-kernel-server mergerfs
```

**Inside LXC - MergerFS fstab:**

```bash
# /etc/fstab (inside LXC)
/mnt/disk1:/mnt/disk2:/mnt/disk3:/mnt/disk4  /mnt/media  fuse.mergerfs  defaults,allow_other,use_ino,cache.files=partial,dropcacheonclose=true,category.create=mfs  0 0
```
```bash
mkdir -p /mnt/media
mount -a
```

**Inside LXC - NFS exports:**

```bash
# /etc/exports
/mnt/nvme   10.0.0.0/16(rw,sync,no_subtree_check,no_root_squash)
/mnt/media  10.0.0.0/16(rw,sync,no_subtree_check,no_root_squash)
```
```bash
exportfs -ra
systemctl enable --now nfs-server
```

**Architecture:**

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

**When migrating NVMe to ZFS:** Just change filesystem on host, LXC sees same bind mount path - no NFS changes needed.

### 1.4 Create K3s VM

- 12 vCPUs, 16GB RAM, 100GB disk (NVMe-backed)
- Network: vmbr1 (10GbE)
- OS: Ubuntu 22.04 LTS or Debian 12
- Static IP: 10.0.1.4

### 1.5 Install kube-vip (Before K3s)

```bash
export VIP=10.0.128.1
export INTERFACE=eth0

sudo mkdir -p /var/lib/rancher/k3s/server/manifests/
curl -sL https://kube-vip.io/manifests/rbac.yaml | sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip-rbac.yaml
```

Create DaemonSet manifest at `/var/lib/rancher/k3s/server/manifests/kube-vip.yaml` with ARP mode, control plane + services enabled.

### 1.5 Install K3s

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --tls-san=${VIP} \
  --tls-san=10.0.1.4
```

Verify: `sudo kubectl get nodes` and `ping 10.0.128.1`

### 1.7 Configure LoadBalancer IP Pool

```bash
kubectl create configmap -n kube-system kubevip \
  --from-literal range-global=10.0.128.2-10.0.128.60
```

### 1.7 Local kubectl Access

```bash
sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
sed -i 's/127.0.0.1/10.0.128.1/g' ~/.kube/config
```

### 1.9 Install Components

**Longhorn:**

```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
```

**cert-manager:**

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
```

**Cloudflare ClusterIssuer + wildcard cert** - see detailed manifests in full plan

---

## Phase 2: NFS Storage for K3s

**Three NFS sources:**

| Source | IP | Export | Contents |

|--------|-----|--------|----------|

| Storage LXC | 10.0.1.2 | /mnt/media | Media library (4x8TB MergerFS) |

| Storage LXC | 10.0.1.2 | /mnt/nvme | Critical data (databases, configs) |

| Old Server | 10.0.1.8 | /mnt/downloads | Download staging area |

**K8s PersistentVolumes:**

```yaml
# Media (MergerFS via LXC)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: media-nfs
spec:
  capacity:
    storage: 32Ti
  accessModes: [ReadWriteMany]
  nfs:
    server: 10.0.1.2
    path: /mnt/media
---
# Critical data (NVMe via LXC)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: critical-nfs
spec:
  capacity:
    storage: 2Ti
  accessModes: [ReadWriteMany]
  nfs:
    server: 10.0.1.2
    path: /mnt/nvme
---
# Downloads (Old Server)
apiVersion: v1
kind: PersistentVolume
metadata:
  name: downloads-nfs
spec:
  capacity:
    storage: 2Ti
  accessModes: [ReadWriteMany]
  nfs:
    server: 10.0.1.8
    path: /mnt/downloads
```

---

## Phase 3: Core Infrastructure

### 3.1 Authentik LXC (Identity Provider)

Deploy Authentik in a dedicated LXC (independent of K3s for resilience).

**Create LXC (10.0.1.3):**
- Template: `debian-12-standard`
- 2 vCPUs, 1-2GB RAM, 10GB disk
- Network: vmbr0, static IP: 10.0.1.3

**Install via Docker Compose:**

```bash
apt update && apt install -y docker.io docker-compose
mkdir -p /opt/authentik && cd /opt/authentik

# Download docker-compose.yml from Authentik docs
curl -sL https://goauthentik.io/docker-compose.yml > docker-compose.yml

# Generate secrets
echo "PG_PASS=$(openssl rand -base64 36)" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60)" >> .env
echo "AUTHENTIK_ERROR_REPORTING__ENABLED=false" >> .env

docker-compose up -d
```

**Key config:**
- PostgreSQL + Redis (included in compose)
- Domain: `auth.yggdrasil.mia.cx` (via Traefik in K3s or direct)
- Create OAuth2/OIDC applications for each service

**Why LXC instead of K3s:**
- Authentik stays up even if K3s is down
- Can authenticate to fix K3s issues
- Independent backup/restore

**SSO Integration by Service:**

| Service | Method | Auto-create users? |

|---------|--------|-------------------|

| Netbird | OIDC | Yes |

| Jellyfin | OIDC (plugin) | Yes, with group-based permissions |

| Nextcloud | OIDC | Yes |

| Forgejo | OIDC | Yes |

| Grafana | OIDC | Yes |

| Proxmox | OIDC (plugin) | Manual |

| Sonarr/Radarr | Proxy auth | N/A (protected, not user-aware) |

### 3.2 Netbird LXC (Management Server)

Deploy Netbird management in a dedicated LXC (independent of K3s).

**Create LXC (10.0.1.5):**
- Template: `debian-12-standard`
- 1-2 vCPUs, 512MB-1GB RAM, 8GB disk
- Network: vmbr0, static IP: 10.0.1.5

**Install via Docker Compose:**

```bash
apt update && apt install -y docker.io docker-compose
mkdir -p /opt/netbird && cd /opt/netbird

# Download docker-compose from Netbird self-hosted docs
# Configure with Authentik OIDC
```

**Authentik OIDC config:**

```yaml
# In Netbird management config
oidc:
  issuer: https://auth.yggdrasil.mia.cx/application/o/netbird/
  clientId: netbird
  clientSecret: <from-authentik>
```

**Why LXC instead of K3s:**
- Netbird management stays up even if K3s is down
- Existing WireGuard tunnels survive management outage
- Can still access infrastructure to fix K3s

### 3.2b Netbird Exit Nodes (K3s DaemonSet)

Exit nodes run in K3s for redundancy across nodes:

```bash
# Deploy exit node DaemonSet after management is up
kubectl apply -f netbird-exit-node-daemonset.yaml
```

Exit nodes connect to management server at 10.0.1.5.

### 3.3 DNS Architecture

**Split-horizon DNS:**

```
External (Cloudflare):
  *.yggdrasil.mia.cx → Cloudflare Workers (landing pages)

Internal (Netbird DNS):
  *.yggdrasil.mia.cx → Internal IPs (100.64.x.x overlay or 10.0.x.x)
```

**Netbird DNS config:**

- Nameserver group pointing to internal DNS (CoreDNS/AdGuard in K3s)
- Match domain: `yggdrasil.mia.cx`
- When connected to Netbird, internal DNS takes precedence

**Internal DNS records (CoreDNS or AdGuard):**

```
hydra.yggdrasil.mia.cx      → 10.0.128.1 (K3s API VIP)
traefik.yggdrasil.mia.cx    → 10.0.128.2 (Traefik VIP)
jellyfin.yggdrasil.mia.cx   → 10.0.128.2
auth.yggdrasil.mia.cx       → 10.0.128.2
*.yggdrasil.mia.cx          → 10.0.128.2 (wildcard to Traefik)
```

### 3.4 Cloudflare Workers (Landing Pages)

For users not on Netbird trying to access internal services:

```javascript
// Worker on *.yggdrasil.mia.cx
const SERVICES = {
  'jellyfin.yggdrasil.mia.cx': { name: 'Jellyfin', icon: '🎬' },
  'proxmox.yggdrasil.mia.cx': { name: 'Proxmox', icon: '🖥️' },
  // ...
};

export default {
  async fetch(request) {
    const host = new URL(request.url).hostname;
    const svc = SERVICES[host] || { name: host.split('.')[0], icon: '🔒' };
    
    return new Response(`
      <html>
        <body style="font-family:system-ui;text-align:center;padding:100px">
          <h1>${svc.icon} ${svc.name}</h1>
          <p>Connect to <b>Yggdrasil</b> network to access this service.</p>
          <a href="https://netbird.io/download">Get Netbird</a>
        </body>
      </html>
    `, { headers: { 'Content-Type': 'text/html' } });
  }
};
```

### 3.5 Traefik Configuration

- Traefik comes pre-installed with K3s
- Add Authentik forward auth middleware for protected routes

**Authentik Forward Auth Middleware:**

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik
  namespace: traefik
spec:
  forwardAuth:
    address: http://authentik-server.authentik/outpost.goauthentik.io/auth/traefik
    trustForwardHeader: true
    authResponseHeaders:
      - X-authentik-username
      - X-authentik-groups
      - X-authentik-email
```

**IngressRoute with SSO:**

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: sonarr
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`sonarr.yggdrasil.mia.cx`)
      kind: Rule
      middlewares:
        - name: authentik  # Requires login
      services:
        - name: sonarr
          port: 8989
  tls:
    certResolver: letsencrypt-cloudflare
```

### 3.6 Jellyfin (Practice Migration)

- Cannot be load-balanced (session state in memory)
- **Install SSO plugin:** `jellyfin-plugin-sso`
- Configure OIDC with Authentik
- Group-based permissions (media-users → User, media-admin → Admin)

**Jellyfin SSO Config:**

```yaml
Providers:
  - Name: Authentik
    OidcClientId: jellyfin
    OidcAuthority: https://auth.yggdrasil.mia.cx/application/o/jellyfin/
    EnableAuthorization: true
    Roles:
      - AuthRole: media-users
        AppRole: User
      - AuthRole: media-admin
        AppRole: Administrator
```

**User onboarding flow:**

1. Create user in Authentik, add to `media-users` group
2. User connects to Netbird (also via Authentik)
3. User visits jellyfin.yggdrasil.mia.cx
4. Clicks "Sign in with Authentik"
5. Account auto-created with correct permissions

---

## Phase 4: Service Migrations

**Order:** Nextcloud, Bitwarden, Plausible, Media stack, Pelican, Forgejo

**For each service:**

1. Create namespace + Longhorn PVC
2. Customize Helm values or write manifests
3. Backup/restore data from old Docker Compose
4. Create IngressRoute, update DNS
5. Decommission old container

**Bitwarden:** Official Helm chart with MSSQL, use `rawManifests` for Traefik IngressRoute

**Media stack:** Sonarr/Radarr mount both NFS shares (downloads + media)

---

## Phase 4B: Workstation VM

- 24 vCPUs, 48GB RAM, RTX 3070 passthrough, vmbr0 (2.5GbE)
- Total 36 vCPUs on 32 threads = mild overcommit (fine)
- Power button toggle script via acpid

---

## Phase 5: Retire Old Server

1. All services migrated and verified
2. Install Proxmox, `pvecm add <workstation-ip>`
3. Restore download disk NFS (LXC or VM)
4. Add K3s server node via VIP

---

## Phase 6: Mini-PCs

- Join as server (control plane) or agent (workloads only)
- Dedicate one to Jellyfin with Intel QuickSync
- Old server can stay as K3s server (extra control plane doesn't hurt)

---

## Key Decisions

| Decision | Choice | Rationale |

|----------|--------|-----------|

| Naming | Yggdrasil (Norse) + Greek deities | World tree connects realms, devices are gods |

| Domain | yggdrasil.mia.cx | Subdomain of existing domain |

| Orchestration | K3s | Lightweight K8s, HA built-in |

| Identity Provider | Authentik LXC (10.0.1.3) | SSO for all services, independent of K3s |

| Overlay network | Netbird LXC (10.0.1.5) + exit nodes in K3s | Management independent, exit nodes distributed |

| Internal DNS | Netbird DNS + CoreDNS | Split-horizon, internal-only resolution |

| External fallback | Cloudflare Workers | Friendly landing pages for non-Netbird users |

| Floating VIPs | kube-vip (ARP) | Single IP for router, auto-failover |

| TLS certs | cert-manager + Cloudflare DNS-01 | Wildcard certs, extractable |

| NFS server | Storage LXC | Separation from host, lightweight (~1GB RAM) |

| Media storage | MergerFS in LXC | Mix disk sizes, easy replacement |

| Critical storage | NVMe (ext4 → ZFS) | Host manages filesystem, LXC exports via NFS |

| K8s storage | Longhorn (small) + NFS (bulk) | Ceph overkill for 1GbE |

| Bitwarden | Official Helm + rawManifest | Full features, not Vaultwarden |

---

## Quick Reference

```bash
# Host storage mounts
df -h /mnt/nvme /mnt/disk{1,2,3,4}

# Storage LXC
pct list                              # List LXC containers
pct enter <id>                        # Enter LXC shell
pct exec <id> -- systemctl status nfs-server

# Inside Storage LXC
df -h /mnt/media /mnt/nvme            # Check mounts
exportfs -v                           # Show NFS exports
cat /proc/fs/nfsd/threads             # NFS threads

# K3s status
sudo kubectl get nodes && sudo kubectl get pods -A

# Join new node via VIP
curl -sfL https://get.k3s.io | sh -s - server \
  --server https://10.0.128.1:6443 --token <token> --tls-san=10.0.128.1

# Check kube-vip
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip
kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip

# Extract certs from secret
kubectl get secret wildcard-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > fullchain.pem
kubectl get secret wildcard-tls -o jsonpath='{.data.tls\.key}' | base64 -d > privkey.pem

# Drain/uncordon node
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>
```