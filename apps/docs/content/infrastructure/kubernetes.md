---
title: Kubernetes (Hydra)
---

# Kubernetes (Hydra)

K3s cluster with kube-vip for high availability.

## K3s VM

| Property | Value |
|----------|-------|
| IP | 10.0.1.4 |
| VMID | 1004 |
| vCPUs | 12 |
| RAM | 16GB |
| Disk | 100GB (NVMe-backed) |
| Network | vmbr1 (10GbE) |
| OS | Ubuntu 22.04 LTS or Debian 12 |

## kube-vip Setup

Install kube-vip **before** K3s:

```bash
export VIP=10.0.128.1
export INTERFACE=eth0

sudo mkdir -p /var/lib/rancher/k3s/server/manifests/
curl -sL https://kube-vip.io/manifests/rbac.yaml | sudo tee /var/lib/rancher/k3s/server/manifests/kube-vip-rbac.yaml
```

Create DaemonSet manifest at `/var/lib/rancher/k3s/server/manifests/kube-vip.yaml` with:
- ARP mode enabled
- Control plane + services enabled

## K3s Installation

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --tls-san=${VIP} \
  --tls-san=10.0.1.4
```

Verify:

```bash
sudo kubectl get nodes
ping 10.0.128.1
```

## LoadBalancer IP Pool

```bash
kubectl create configmap -n kube-system kubevip \
  --from-literal range-global=10.0.128.2-10.0.128.60
```

## Local kubectl Access

```bash
sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config
sed -i 's/127.0.0.1/10.0.128.1/g' ~/.kube/config
```

## Core Components

### Longhorn (Distributed Storage)

```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
```

### cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml
```

### Cloudflare ClusterIssuer

For DNS-01 wildcard certificates - see [[../services/traefik|Traefik configuration]].

## NFS PersistentVolumes

Three NFS sources for K3s:

| Source | IP | Export | Contents |
|--------|-----|--------|----------|
| Storage LXC | 10.0.1.2 | /mnt/media | Media library |
| Storage LXC | 10.0.1.2 | /mnt/nvme | Critical data |
| Old Server | 10.0.1.8 | /mnt/downloads | Download staging |

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

## Adding Nodes

Join new nodes via VIP:

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --server https://10.0.128.1:6443 \
  --token <token> \
  --tls-san=10.0.128.1
```

## Node Management

```bash
# Drain node for maintenance
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Return node to service
kubectl uncordon <node>
```
