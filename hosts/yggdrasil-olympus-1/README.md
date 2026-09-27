# yggdrasil-olympus-1

Primary NetBird server (Management, Signal, Relay, embedded IdP) on a Proxmox
VM at `10.0.1.4` (VMID 1004 on athena). Replaces the dead management LXC;
nothing migrated from it. Public HTTPS goes through the K3s Traefik, which
forwards to the VM Traefik on `:8080`. Guest port `:8443` answers directly
with its own certificate for diagnosis and K3s-independent access.

Stack: Traefik v3.7.13, netbird-server 0.79.0, dashboard v2.92.0, and a
netbird 0.79.0 client (netbird-router) that routes the mesh into the LAN.
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

## Hecate login

Sign-in has two paths. People use the `Hecate` OIDC connector on the login
page. The embedded local admin stays enabled as break-glass.

The OIDC application and permission groups live in the repo at
`argocd/authentik/netbird-blueprint.yaml`. The blueprint sets
`grant_types: [authorization_code, refresh_token]` because
blueprint-created providers start with none. NetBird's generic OIDC
connector asks only for `openid profile email`, so the blueprint puts the
`groups` claim in the `profile` scope. The client secret lives in the K8s
Secret `netbird-oidc` (namespace `authentik`, key `client-secret`) and in
`~/.config/yggdrasil/netbird-hecate-oidc.env` on this Mac.

The connector and the account settings live in the NetBird database, not
in `config.yaml.tmpl`, so a rebuild must recreate them:

1. Create the connector. The client secret comes from the Mac file:

   ```bash
   source ~/.config/yggdrasil/netbird-hecate-oidc.env
   curl -sf -X POST https://netbird.mia.cx/api/identity-providers \
     -H "Authorization: Token $(cat ~/.config/yggdrasil/netbird-primary.pat)" \
     -H "Content-Type: application/json" \
     -d "{\"name\":\"Hecate\",\"type\":\"oidc\",\"issuer\":\"https://id.mia.cx/application/o/netbird/\",\"client_id\":\"netbird\",\"client_secret\":\"$NETBIRD_OIDC_CLIENT_SECRET\"}"
   ```

2. Apply the account settings. `PUT` replaces the whole settings object,
   so read it, change the auth keys, and send it back:

   ```bash
   api=https://netbird.mia.cx/api
   auth="Authorization: Token $(cat ~/.config/yggdrasil/netbird-primary.pat)"
   account=$(curl -sf -H "$auth" $api/accounts | jq '.[0]')
   echo "$account" | jq '{settings: (.settings + {
       jwt_groups_enabled: true,
       jwt_groups_claim_name: "groups",
       jwt_allow_groups: ["netbird-enroll"],
       groups_propagation_enabled: true,
       peer_login_expiration_enabled: true,
       peer_login_expiration: 2592000
     } | .extra.user_approval_required = false)}' |
     curl -sf -X PUT -H "$auth" -H "Content-Type: application/json" \
       -d @- "$api/accounts/$(echo "$account" | jq -r .id)" > /dev/null
   ```

   `peer_login_expiration` is in seconds; 2592000 is 30 days.
   `jwt_allow_groups` blocks sign-in for users without `netbird-enroll`.

3. Sign in once through Hecate with an account in `role-admin` so NetBird
   recreates the JWT-issued groups.

## LAN routing client

`netbird-router` is a NetBird client peer, not part of the server: host
network, kernel WireGuard (`wt0`), masquerading mesh traffic onto the LAN.
It restarts with the rest of the stack (`restart: unless-stopped` from the
compose anchor), so a VM reboot needs no manual step.

NetBird objects (all in the primary account, by name):

- Group `routers-olympus` — holds the routing peer.
- Network `olympus-lan` — resource `10.0.0.0/16`, routing group
  `routers-olympus`, masquerade on, metric 9999.
- Policy `olympus-lan` — grants a source group access to that resource. The
  intended source is the JWT group `svc-lan`; until Hecate issues it, the
  temporary `test-lan` group stands in. The `Default` policy is untouched;
  network resources are only reachable through policies that target them.

No ufw rule is needed: NetBird inserts its own wt0 accept rules ahead of
ufw/Docker and enforces access through NetBird policies.

Enrolling after a rebuild or a lost `netbird_router` volume: mint a one-off
setup key (auto-group `routers-olympus`, 24h expiry) in the dashboard or via
the admin API, set `NB_ROUTER_SETUP_KEY` in `.env`, then:

```bash
sudo docker compose up -d netbird-router
sudo docker compose exec netbird-router netbird status -d
# expect: Interface type: Kernel, Networks: 10.0.0.0/16
```

## Upgrading versions

Image tags are pinned in `compose.yaml`. Bump the tag, then
`sudo docker compose pull && sudo docker compose up -d`. Check the NetBird
release notes for config changes; `config.yaml.tmpl` follows the combined
server schema (`combined/config.yaml.example` in netbirdio/netbird).

## External relay

The primary mesh does not run its own relay or STUN. `config.yaml.tmpl`
points peers at `rels://netbird-relay.mia.cx:443` and
`stun:netbird-relay.mia.cx:3479`, which run on the Repair VPS
(`hosts/yggdrasil-repair-1`); setting `relays` also turns off the embedded
relay here.

`NETBIRD_RELAY_AUTH_SECRET` in `/opt/netbird/.env` must equal the value in
`/opt/netbird/.env` on `yggdrasil-repair-1`. To rotate it: generate a new
value into both `.env` files, re-render `config.yaml` here, restart
`netbird-server` on this VM, and `docker compose restart relay` on the VPS.
