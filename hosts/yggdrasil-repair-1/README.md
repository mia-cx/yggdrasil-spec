# yggdrasil-repair-1

Independent Repair mesh on a Hetzner CX23 (`178.105.231.90`, nbg1). Runs a
complete NetBird stack for `netbird-repair.mia.cx` (Management, Signal,
embedded Relay + STUN, embedded IdP) and, on the same VPS, the relay + STUN
that the primary mesh uses (`netbird-relay.mia.cx`, STUN on UDP 3479).
The two roles share the host and Traefik but nothing else: no secrets,
accounts, or state cross between them.

Stack: Traefik v3.7.13, netbird-server 0.79.0, dashboard v2.92.0,
netbirdio/relay 0.79.0. TLS is Let's Encrypt HTTP-01. This host must stay
useful when everything at home is down, so it depends on nothing there (no
Cloudflare DNS-01, no LAN trust).

## Secrets

`/opt/netbird/.env` on the VPS (root, `0600`) holds the only secrets: the
local admin credentials and the NetBird secrets rendered into `config.yaml`.
First boot generates `.env` with fresh random values
(`NETBIRD_ADMIN_EMAIL=repair-admin@mia.cx`); the repo has `.env.example`
with the variable names. `config.yaml` is generated and also secret-bearing;
keep it root `0600`.

`NETBIRD_RELAY_AUTH_SECRET` is shared with the primary server only; the same
value lives in `/opt/netbird/.env` on `yggdrasil-olympus-1` so the primary
mesh can use `netbird-relay.mia.cx`.

## Changing the stack

The server is provisioned once by cloud-init; editing files in the repo does
not change the VPS (and must never rebuild it, see below). To apply edits:

```bash
ssh mia@178.105.231.90 mkdir -p /tmp/netbird
scp hosts/yggdrasil-repair-1/{compose.yaml,traefik.yaml,dynamic.yaml,config.yaml.tmpl,dashboard.env} \
  mia@178.105.231.90:/tmp/netbird/
ssh mia@178.105.231.90
```

On the VPS:

```bash
sudo cp /tmp/netbird/* /opt/netbird/ && rm -rf /tmp/netbird
cd /opt/netbird
sudo bash -c 'set -a; . ./.env; set +a; \
  export NETBIRD_ADMIN_PASSWORD_HASH=$(htpasswd -bnBC 12 "" "$NETBIRD_ADMIN_PASSWORD" | tr -d ":\n"); \
  envsubst < config.yaml.tmpl > config.yaml'
sudo chmod 600 config.yaml
sudo docker compose up -d
```

`.env` is sourced as shell code, so every value must stay shell-safe: no `$`,
spaces, quotes, or backticks (hex/base64 output is safe).

## OpenTofu

`terraform/repair` owns the VPS, its primary IPs, the Hetzner firewall, and
the `netbird-repair`/`netbird-relay` DNS records. Tokens come from the
environment only:

```bash
export HCLOUD_TOKEN="$(cat ~/.config/yggdrasil/hcloud-token)"
export CLOUDFLARE_API_TOKEN="<dns-edit token for mia.cx>"
cd terraform/repair
tofu init
tofu plan
```

`hcloud_server.repair` has `lifecycle { ignore_changes = [user_data] }`:
editing stack files must never silently rebuild a stateful server. A rebuild
is always explicit:

```bash
tofu apply -replace=hcloud_server.repair
```

After a replacement the host key changes. Run
`ssh-keygen -R 178.105.231.90` locally before SSHing back in.

If state is lost, re-import the existing resources. SSH key and primary IP
IDs are stable; the server ID changes on every rebuild, so look up the
current one first (`curl -H "Authorization: Bearer $HCLOUD_TOKEN"
https://api.hetzner.cloud/v1/servers?name=yggdrasil-repair-1`):

```bash
tofu import hcloud_ssh_key.mia 130550689
tofu import hcloud_primary_ip.ipv4 151842311
tofu import hcloud_primary_ip.ipv6 151842312
tofu import hcloud_server.repair <current-server-id>
# DNS records (only if they were already created): cloudflare_dns_record uses
# <zone_id>/<record_id>; get IDs from the Cloudflare dashboard or API.
```

The primary IPs carry `delete_protection` and `prevent_destroy`; the
firewall opens TCP 22/80/443, UDP 3478 (Repair STUN), UDP 3479 (primary-mesh
relay STUN), and ICMP.

### Adopting a hand-bought server

Primary IPs created by a server order start with `auto_delete=true`, which
would silently delete them when the server is replaced. After importing an
existing server, land `auto_delete=false` and `delete_protection=true` in a
targeted apply first, then replace the server in a second step:

```bash
tofu apply -target=hcloud_primary_ip.ipv4 -target=hcloud_primary_ip.ipv6
tofu apply -replace=hcloud_server.repair
```

## Backup and restore

The state that matters is `/opt/netbird/.env` (secrets) and the
`netbird_netbird_data` volume (sqlite store). Back it up encrypted to this
Mac; the passphrase lives in `~/.config/yggdrasil/repair-backup-passphrase`
(local copy) and in Mia's password manager (the real copy):

```bash
ssh mia@178.105.231.90 'cd /opt/netbird && sudo docker compose stop netbird-server && \
  sudo tar -C / -czf - opt/netbird/.env var/lib/docker/volumes/netbird_netbird_data/_data; \
  sudo docker compose start netbird-server' \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
      -pass file:$HOME/.config/yggdrasil/repair-backup-passphrase \
      -out ~/.config/yggdrasil/backups/repair-$(date +%Y%m%d).tar.gz.enc
```

To verify a backup without touching the live stack, restore into a scratch
dir and run a throwaway server against it:

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -pass file:$HOME/.config/yggdrasil/repair-backup-passphrase \
  -in ~/.config/yggdrasil/backups/repair-<date>.tar.gz.enc \
  | ssh mia@178.105.231.90 'sudo mkdir -p /tmp/repair-restore && sudo tar -C /tmp/repair-restore -xzf -'
```

On the VPS, render a config from the restored `.env` and the live template,
then start a scratch compose project with only `netbird-server` (restored
`_data` bind-mounted at `/var/lib/netbird`, own network, no published
ports). `GET http://netbird-server:80/api/users` with the repair PAT from
another container on that network proves the store decrypted and works.
Tear down with `docker compose down` and `sudo rm -rf /tmp/repair-restore`.

Full rebuild after losing the server: `tofu plan`, then
`tofu apply -replace=hcloud_server.repair`, wait for
`sudo cloud-init status --wait` (bootstrap generates a fresh `.env` and
starts the stack), then on the VPS `cd /opt/netbird && sudo docker compose
down`, untar the archive over `/` (restores `.env` and the volume data),
re-render `config.yaml` as above, and `sudo docker compose up -d`. Without a
backup the rebuild generates a new `NETBIRD_RELAY_AUTH_SECRET`, which then
has to be copied into `/opt/netbird/.env` on `yggdrasil-olympus-1` and the
primary's `config.yaml` re-rendered and restarted.

## Mia's devices

Setup key: `mia-devices`, reusable, in
`~/.config/yggdrasil/repair-setup-key` on the Mac.

Desktop (macOS/Linux) uses a second profile so the primary mesh stays
untouched:

```bash
netbird profile add repair
netbird profile select repair
netbird up --management-url https://netbird-repair.mia.cx \
  --setup-key-file ~/.config/yggdrasil/repair-setup-key
```

Switch back with `netbird profile select default` (or pick the profile in
the tray menu / Settings then Profiles in the desktop app).

Phones have no profiles: the iOS/Android apps only offer "Change Server"
(hamburger menu), which erases the device's current NetBird config. To put
a phone on the Repair mesh, set the server to
`https://netbird-repair.mia.cx` there and paste the `mia-devices` key under
"Add this device with a setup key". Switching back means changing the
server again and re-authenticating, so treat the phone as one mesh at a
time.
