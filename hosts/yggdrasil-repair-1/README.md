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

If state is lost, re-import every resource. The SSH key, primary IP,
firewall, and DNS record IDs are stable unless the object is recreated; the
server ID changes on every rebuild. Look IDs up by name when unsure:

```bash
# Hetzner (substitute ssh_keys, primary_ips, firewalls, servers and the
# names from terraform/repair/main.tf):
curl -sH "Authorization: Bearer $HCLOUD_TOKEN" \
  'https://api.hetzner.cloud/v1/servers?name=yggdrasil-repair-1'
# Cloudflare (zone mia.cx; filter further by type A or AAAA):
curl -sH "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  'https://api.cloudflare.com/client/v4/zones/75fd0dd1afc13e40321b1fcc68a9dbdd/dns_records?name=netbird-repair.mia.cx'
```

Import order: firewall before server, since the server references it.

```bash
tofu import hcloud_ssh_key.mia 130550689
tofu import hcloud_primary_ip.ipv4 151842311
tofu import hcloud_primary_ip.ipv6 151842312
tofu import hcloud_firewall.repair 11689707
tofu import hcloud_server.repair <current-server-id>
tofu import cloudflare_dns_record.netbird_repair_a 75fd0dd1afc13e40321b1fcc68a9dbdd/508cfe414ae8c33d46f4e015f1559801
tofu import cloudflare_dns_record.netbird_repair_aaaa 75fd0dd1afc13e40321b1fcc68a9dbdd/46bbaec8056e8f1a0c4726b06f94507a
tofu import cloudflare_dns_record.netbird_relay_a 75fd0dd1afc13e40321b1fcc68a9dbdd/a285a225b7d0a4874e881ae14612f2f8
tofu import cloudflare_dns_record.netbird_relay_aaaa 75fd0dd1afc13e40321b1fcc68a9dbdd/e78a6bad5010bed60690e5932e893f0e
```

`ssh_keys` is a create-only attribute the provider cannot read back after an
import, so the server ignores changes to it; a fresh import plans no
replacement. Rebuild with `-replace` only when you intend to.

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

The backup runs in a subshell so `pipefail` and `umask` do not leak into
your shell; `netbird-server` is started again even when `tar` fails; any
failing stage makes the command exit non-zero and leaves the previous
archive untouched:

```bash
(
  set -o pipefail
  umask 077
  out=~/.config/yggdrasil/backups/repair-$(date +%Y%m%d).tar.gz.enc
  ssh mia@178.105.231.90 'cd /opt/netbird || exit 1
    sudo docker compose stop netbird-server &&
      sudo tar -C / -czf - opt/netbird/.env var/lib/docker/volumes/netbird_netbird_data/_data
    rc=$?
    sudo docker compose start netbird-server || rc=1
    exit $rc' |
    openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
      -pass file:"$HOME/.config/yggdrasil/repair-backup-passphrase" -out "$out.tmp" &&
    mv "$out.tmp" "$out" || { rm -f "$out.tmp"; exit 1; }
)
```

Check a fresh archive lists cleanly without extracting it:

```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
  -pass file:"$HOME/.config/yggdrasil/repair-backup-passphrase" \
  -in ~/.config/yggdrasil/backups/repair-<date>.tar.gz.enc | tar -tzf - >/dev/null && echo ok
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
re-render `config.yaml` as above, and `sudo docker compose up -d`.

### Relay secret after a restore

Every restore, with or without a backup, can leave the primary's copy of
`NETBIRD_RELAY_AUTH_SECRET` out of date: a rebuild without a backup
generates a new one, and a backup restored later brings back whatever value
was current when it was taken. Compare the two hosts by hash, never by
printing the value:

```bash
ssh mia@178.105.231.90 sudo grep '^NETBIRD_RELAY_AUTH_SECRET=' /opt/netbird/.env | shasum -a 256
ssh mia@10.0.1.4 sudo grep '^NETBIRD_RELAY_AUTH_SECRET=' /opt/netbird/.env | shasum -a 256
```

If they differ, make the primary match the VPS, because the relay on the VPS
is what authenticates:

```bash
ssh mia@178.105.231.90 sudo grep '^NETBIRD_RELAY_AUTH_SECRET=' /opt/netbird/.env \
  | ssh mia@10.0.1.4 'sudo sed -i "/^NETBIRD_RELAY_AUTH_SECRET=/d" /opt/netbird/.env && sudo tee -a /opt/netbird/.env >/dev/null'
```

Then on the VM re-render `config.yaml` and restart `netbird-server` as in
the [External relay](../yggdrasil-olympus-1/README.md#external-relay)
section of the primary's README.

Rotating the relay secret means taking a fresh backup right away, or a later
restore brings back the old value.

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
