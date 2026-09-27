# yggdrasil-olympus-1

Primary NetBird server (Management, Signal, Relay, embedded IdP) on a Proxmox
VM at `10.0.1.4` (VMID 1004 on athena). Replaces the dead management LXC;
nothing migrated from it. Public HTTPS goes through the K3s Traefik, which
forwards to the VM Traefik on `:8080`. Guest port `:8443` answers directly
with its own certificate for diagnosis and K3s-independent access.

Stack: Traefik v3.7.13, netbird-server 0.79.0, dashboard v2.92.0.
Hecate SSO replaces the embedded IdP in a later step; relay/STUN moves to the
Repair VPS later too — `config.yaml.tmpl` marks the temporary Cloudflare STUN.

## Secrets

`/opt/netbird/.env` on the VM (root, `0600`) holds the only secrets: the
Cloudflare DNS token, the local admin credentials, and the NetBird secrets
that are rendered into `config.yaml`. The repo has `.env.example` with the
variable names. `config.yaml` itself is generated and also secret-bearing;
keep it root `0600`.

## Rebuild from scratch

```bash
# On athena as root: create the snippet, then the VM
scp hosts/yggdrasil-olympus-1/user-data.yaml \
  root@10.0.1.1:/var/lib/vz/snippets/yggdrasil-olympus-1-user-data.yaml
ssh root@10.0.1.1 'cd /var/lib/vz/template/iso \
  && curl -sfLO https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2 \
  && curl -sf https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS \
  | grep genericcloud-amd64.qcow2 | sha512sum -c -'
ssh root@10.0.1.1 'qm create 1004 --name yggdrasil-olympus-1 --ostype l26 \
  --memory 4096 --balloon 0 --cores 2 --cpu host \
  --net0 virtio,bridge=vmbr0,firewall=1 --scsihw virtio-scsi-single \
  --agent 1 --onboot 1 --tags netbird --numa 0 \
  && qm importdisk 1004 /var/lib/vz/template/iso/debian-13-genericcloud-amd64.qcow2 local-lvm \
  && qm set 1004 --scsi0 local-lvm:vm-1004-disk-0,discard=on,iothread=1,ssd=1 \
  && qm resize 1004 scsi0 32G \
  && qm set 1004 --ide2 local-lvm:cloudinit --boot order=scsi0 \
  && qm set 1004 --cicustom user=local:snippets/yggdrasil-olympus-1-user-data.yaml \
     --ipconfig0 ip=10.0.1.4/16,gw=10.0.0.1 --nameserver "10.0.0.1 1.1.1.1" \
  && qm start 1004'

# Wait for cloud-init (installs Docker CE, enables ufw), then deploy the stack
scp -r hosts/yggdrasil-olympus-1 mia@10.0.1.4:/tmp/netbird
ssh mia@10.0.1.4 'sudo cp -r /tmp/netbird/. /opt/netbird/ && rm -rf /tmp/netbird'
ssh mia@10.0.1.4
```

On the VM:

```bash
cd /opt/netbird
sudo cp .env.example .env && sudo chmod 600 .env
# Fill .env: CF token (same as cluster secret cert-manager/cloudflare-api-token),
# admin email/password, and fresh random values, e.g.:
#   openssl rand -base64 32        # NETBIRD_AUTH_SECRET, NB_SESSION_COOKIE_ENCRYPTION_KEY
#   openssl rand -base64 32        # NETBIRD_STORE_ENCRYPTION_KEY
#   openssl rand -hex 24           # NETBIRD_ADMIN_PASSWORD
# .env is sourced as shell code, so every value must stay shell-safe:
# no $, spaces, quotes, or backticks (hex/base64 output is safe).
sudo bash -c 'set -a; . ./.env; set +a; \
  export NETBIRD_ADMIN_PASSWORD_HASH=$(htpasswd -bnBC 12 "" "$NETBIRD_ADMIN_PASSWORD" | tr -d ":\n"); \
  envsubst < config.yaml.tmpl > config.yaml'
sudo chmod 600 config.yaml
sudo docker compose up -d
sudo docker compose ps
```

## Upgrading versions

Image tags are pinned in `compose.yaml`. Bump the tag, then
`sudo docker compose pull && sudo docker compose up -d`. Check the NetBird
release notes for config changes; `config.yaml.tmpl` follows the combined
server schema (`combined/config.yaml.example` in netbirdio/netbird).
