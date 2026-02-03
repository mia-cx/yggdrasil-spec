---
title: Quick Reference
---

# Quick Reference

Common commands and quick lookups.

## IP Addresses & VMIDs

| Entity | IP | VMID |
|--------|-----|------|
| Proxmox host | 10.0.1.1 | - |
| Storage LXC | 10.0.1.2 | 1002 |
| Authentik LXC | 10.0.1.3 | 1003 |
| K3s VM | 10.0.1.4 | 1004 |
| Netbird LXC | 10.0.1.5 | 1005 |
| Wings VM | 10.0.1.6 | 1006 |
| Old Server | 10.0.1.8 | - |
| Old Server K3s | 10.0.1.9 | 1009 |
| Workstation VM | 10.0.3.1 | 3001 |
| K3s API VIP | 10.0.128.1 | - |
| Traefik VIP | 10.0.128.2 | - |

**VMID Pattern:** `(3rd_octet × 1000) + last_octet`

## Proxmox Commands

```bash
# List LXC containers
pct list

# Enter LXC shell
pct enter <id>

# Execute command in LXC
pct exec <id> -- <command>

# Start/stop LXC
pct start <id>
pct stop <id>

# List VMs
qm list

# Start/stop VM
qm start <id>
qm stop <id>
```

## Storage LXC

```bash
# Check mounts
df -h /mnt/media /mnt/nvme

# Show NFS exports
exportfs -v

# NFS threads
cat /proc/fs/nfsd/threads

# Restart NFS
systemctl restart nfs-server
```

## K3s / Kubernetes

```bash
# Cluster status
sudo kubectl get nodes
sudo kubectl get pods -A

# Watch pods
kubectl get pods -A -w

# Describe resource
kubectl describe pod <name> -n <namespace>

# Logs
kubectl logs <pod> -n <namespace>
kubectl logs -f <pod> -n <namespace>  # follow

# Check kube-vip
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip
kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip
```

## Node Management

```bash
# Drain node for maintenance
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Return node to service
kubectl uncordon <node>

# Join new node via VIP
curl -sfL https://get.k3s.io | sh -s - server \
  --server https://10.0.128.1:6443 \
  --token <token> \
  --tls-san=10.0.128.1
```

## Certificates

```bash
# Extract certs from K8s secret
kubectl get secret wildcard-tls -n traefik -o jsonpath='{.data.tls\.crt}' | base64 -d > fullchain.pem
kubectl get secret wildcard-tls -n traefik -o jsonpath='{.data.tls\.key}' | base64 -d > privkey.pem

# Check cert expiry
openssl x509 -in fullchain.pem -noout -enddate
```

## Docker (LXCs)

```bash
# Authentik LXC
cd /opt/authentik
docker-compose logs -f
docker-compose restart

# Netbird LXC
cd /opt/netbird
docker-compose logs -f
docker-compose restart
```

## Debugging

```bash
# Test NFS mount
mount -t nfs 10.0.1.2:/mnt/media /mnt/test

# Test DNS resolution
dig jellyfin.yggdrasil.mia.cx
nslookup jellyfin.yggdrasil.mia.cx

# Check Traefik routes
kubectl get ingressroutes -A

# Check services
kubectl get svc -A
```

## Helm

```bash
# List releases
helm list -A

# Show values
helm get values <release> -n <namespace>

# Upgrade
helm upgrade <release> <chart> -n <namespace> -f values.yaml
```

## Backup Commands

```bash
# Authentik PostgreSQL
docker exec authentik-postgresql pg_dump -U authentik authentik > backup.sql

# Restore
cat backup.sql | docker exec -i authentik-postgresql psql -U authentik authentik
```

## URLs

| Service | URL |
|---------|-----|
| Authentik | https://auth.yggdrasil.mia.cx |
| Jellyfin | https://jellyfin.yggdrasil.mia.cx |
| Proxmox | https://10.0.1.1:8006 |
| Longhorn | https://longhorn.yggdrasil.mia.cx |
| Grafana | https://grafana.yggdrasil.mia.cx |
