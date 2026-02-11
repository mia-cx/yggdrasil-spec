---
title: Runbooks
---

# Runbooks

Common command recipes grouped by component.

## Proxmox

```bash
# List LXC containers
pct list

# Enter LXC shell
pct enter <id>

# Execute command in LXC
pct exec <id> -- <command>

# LXCs do not share the Proxmox host password or SSH keys — each container has its own
# /etc/passwd and root home. To enable SSH key login: from the host run
#   pct enter <id>
# then create /root/.ssh (mode 700), add your public key to /root/.ssh/authorized_keys (600),
# and ensure sshd has PubkeyAuthentication yes. Or one-liner from host:
#   pct exec <id> -- bash -c 'mkdir -p /root/.ssh && echo "YOUR_PUBKEY" >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys'

# Start/stop LXC
pct start <id>
pct stop <id>

# List VMs
qm list

# Start/stop VM
qm start <id>
qm stop <id>
```

### Moving VM disks or CT volumes to different storage (e.g. local-lvm → local)

Use this when you want to move disks off `local-lvm` (LVM-thin) to `local` (directory) or another storage—e.g. before disks grow too large to move comfortably, or to rebalance space.

**Caveats:**

- Target storage must have enough free space for a **full copy** of the disk/volume during the move. Moving from `local-lvm` to `local` frees space in the LVM pool but uses space on the same root disk; ensure `local` (e.g. `/var/lib/vz`) has room.
- Move **one VM or CT at a time**; optionally delete the source after each move so space is freed before the next.
- **Stop** the VM or CT before moving (recommended for a clean move). VM live-move to another storage type on the same node is not guaranteed.
- If the VM has **snapshots**, consider consolidating or moving the base disk first; snapshot chains can complicate moves.

**VM disk (UI):**

1. Stop the VM.
2. VM → **Hardware** → select the disk (e.g. scsi0) → **Move disk**.
3. Choose **Target storage** (e.g. `local`). Optionally enable **Delete source** after success.
4. Start the VM when the move finishes.

**VM disk (CLI):**

```bash
# Move disk (VMID 1003, disk scsi0) to storage 'local'
qm move-disk 1003 scsi0 local

# Optional: remove source after move
qm move-disk 1003 scsi0 local --delete 1
```

**CT volume (UI):**

1. Stop the container.
2. **Datacenter** → **Storage** → select source storage (e.g. local-lvm) → **Content**.
3. Select the CT volume (e.g. `vm-101-disk-0`) → **Move** → choose target storage (e.g. `local`).

**CT volume (CLI):**

```bash
# List volumes on source storage to get the volid
pvesm list local-lvm

# Move volume (example)
pvesm move vm-101-disk-0 local
```

Then start the container.

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
kubectl get secret wildcard-tls -n traefik \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > fullchain.pem
kubectl get secret wildcard-tls -n traefik \
  -o jsonpath='{.data.tls\.key}' | base64 -d > privkey.pem

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

## Helm

```bash
# List releases
helm list -A

# Show values
helm get values <release> -n <namespace>

# Upgrade
helm upgrade <release> <chart> -n <namespace> -f values.yaml
```

## Backup & Restore

```bash
# Authentik PostgreSQL
docker exec authentik-postgresql pg_dump -U authentik authentik > backup.sql

# Restore
cat backup.sql | docker exec -i authentik-postgresql psql -U authentik authentik
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
