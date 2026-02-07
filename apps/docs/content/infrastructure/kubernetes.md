---
title: Kubernetes
---

# Kubernetes (Hydra)

## Overview

| Property | Value               |
| -------- | ------------------- |
| Type     | VM                  |
| IP       | 10.0.1.3            |
| VMID     | 1003                |
| vCPUs    | 12                  |
| RAM      | 16GB                |
| Disk     | 100GB (NVMe-backed) |
| Network  | vmbr0 (2.5GbE)      |
| OS       | Debian 13           |
| API VIP  | 10.0.128.1          |

K3s cluster with kube-vip for high availability. Control plane is accessed via the VIP at `10.0.128.1`.

## Prerequisites

- Proxmox VM created with the specs above
- Debian 13 netinst ISO

## Setup

### Proxmox VM Settings

| Setting       | Value    |
| ------------- | -------- |
| CPU type      | `host`   |
| Ballooning    | Disabled |
| Disk cache    | `none`   |
| SSD emulation | Yes      |
| Discard       | Yes      |
| IO Thread     | Yes      |

### OS Installation

1. Download Debian 13 netinst ISO
2. Regular install (not graphical)
3. Hostname: `hydra-olympus-X`
4. Domain: `yggdrasil.mia.cx`
5. Create user
6. Partitioning: use entire disk, no LVM
7. Software: SSH server + standard utilities only

### Base Configuration

**Sudo access:**

```bash
# As root (su -)
apt install sudo
usermod -aG sudo mia
```

**Static network** (`/etc/network/interfaces`):

```bash
allow-hotplug ens18
iface ens18 inet static
    address 10.0.1.3
    netmask 255.255.0.0
    gateway 10.0.0.1
    dns-nameservers 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4
```

**Fix DNS resolution:**

```bash
sudo apt install resolvconf
sudo systemctl restart networking
```

**SSH hardening:**

```bash
ssh-copy-id mia@10.0.1.3
```

Edit `/etc/ssh/sshd_config`:

```bash
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowAgentForwarding no
AllowTcpForwarding yes
```

```bash
sudo systemctl restart sshd
```

**QEMU guest agent:**

```bash
sudo apt install qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

**NFS client** (required for NFS PVs):

```bash
sudo apt install nfs-common
```

**Increase inotify limits** (default limits are too low for K3s workloads):

```bash
sudo tee /etc/sysctl.d/99-k3s.conf << 'EOF'
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 524288
EOF
sudo sysctl --system
```

### kube-vip

Install kube-vip **before** K3s:

```bash
sudo mkdir -p /var/lib/rancher/k3s/server/manifests/
sudo mkdir -p /var/lib/rancher/k3s/agent/pod-manifests/

# Download RBAC (for multi-node leader election)
curl -sL https://kube-vip.io/manifests/rbac.yaml \
  | sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip-rbac.yaml

# Copy static pod manifest
sudo cp argocd/k3s/kube-vip.yaml /var/lib/rancher/k3s/agent/pod-manifests/kube-vip.yaml
```

### K3s Installation

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --tls-san=${VIP} \
  --tls-san=10.0.1.3 \
  --disable=servicelb
```

### LoadBalancer IP Pool

```bash
sudo kubectl create configmap -n kube-system kubevip \
  --from-literal range-global=10.0.128.2-10.0.128.60
```

### Local kubectl Access

```bash
sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
sed -i 's/127.0.0.1/10.0.128.1/g' ~/.kube/config
```

## Configuration

### Core Components

**Longhorn (distributed storage):**

```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
```

**cert-manager:**

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
```

**Cloudflare ClusterIssuer:** See [Traefik -- TLS](./traefik.md#setup).

### NFS PersistentVolumes

| Source      | IP       | Export         | Contents         |
| ----------- | -------- | -------------- | ---------------- |
| Storage LXC | 10.0.1.2 | /mnt/media     | Media library    |
| Storage LXC | 10.0.1.2 | /mnt/nvme      | Critical data    |
| Old Server  | 10.0.1.8 | /mnt/downloads | Download staging |

```bash
kubectl apply -f argocd/k3s/nfs-pvs.yaml
```

### Adding Nodes

Join new nodes via VIP:

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --server https://10.0.128.1:6443 \
  --token <token> \
  --tls-san=10.0.128.1
```

### Node Management

```bash
# Drain node for maintenance
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Return node to service
kubectl uncordon <node>
```

## Verification

```bash
sudo kubectl get nodes
ping 10.0.128.1
kubectl get pods -A
```
