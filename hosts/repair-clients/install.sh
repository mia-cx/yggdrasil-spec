#!/usr/bin/env bash
# Install or re-enroll the unprivileged Repair netstack client on a host.
# Run ON the host as root:
#   ./install.sh <netbird-hostname>   # with the setup key on stdin
# e.g. cat ~/.config/yggdrasil/repair-key-guests | ssh root@HOST \
#        'bash /tmp/repair-clients/install.sh hephaestus'
# The key never enters argv; it lands 0600 in the state dir and is deleted
# once the peer registers.
set -euo pipefail

VERSION=0.79.0
BASE="https://github.com/netbirdio/netbird/releases/download/v${VERSION}"
TARBALL="netbird_${VERSION}_linux_amd64.tar.gz"
SUMS="netbird_${VERSION}_checksums.txt"
PREFIX=/usr/local/lib/netbird-repair
STATE=/var/lib/netbird-repair
RUNDIR=/run/netbird-repair
UNIT=/etc/systemd/system/netbird-repair.service
MGMT=https://netbird-repair.mia.cx
WG_PORT=51821

NB_HOSTNAME="${1:?usage: install.sh <netbird-hostname> (setup key on stdin)}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }
NB_CLI="$PREFIX/netbird --daemon-addr unix://$RUNDIR/netbird.sock"
# Mirror the unit env for CLI calls so the daemon and CLI agree on paths.
export NB_CONFIG="$STATE/config.json" NB_STATE_DIR="$STATE" \
  NB_USE_NETSTACK_MODE=true NB_ENABLE_NETSTACK_LOCAL_FORWARDING=true \
  NB_DISABLE_DNS=true NB_NETSTACK_SKIP_PROXY=true

# --- user and dirs -------------------------------------------------------
id -u netbird-repair >/dev/null 2>&1 ||
  useradd --system --no-create-home --shell /usr/sbin/nologin netbird-repair
install -d -m 0755 "$PREFIX"
install -d -o netbird-repair -g netbird-repair -m 0750 "$STATE" /var/log/netbird-repair

# --- binary --------------------------------------------------------------
if ! "$PREFIX/netbird" version 2>/dev/null | grep -q "$VERSION"; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "$BASE/$TARBALL" -o "$tmp/$TARBALL"
  curl -fsSL "$BASE/$SUMS" -o "$tmp/$SUMS"
  (cd "$tmp" && grep " $TARBALL\$" "$SUMS" | sha256sum --check -)
  tar -xzf "$tmp/$TARBALL" -C "$tmp" netbird
  install -m 0755 -o root -g root "$tmp/netbird" "$PREFIX/netbird"
fi
"$PREFIX/netbird" version

# --- setup key (stdin -> 0600 state file, deleted after enrollment) ------
key_file="$STATE/setup-key"
umask 077
cat >"$key_file"
chown netbird-repair:netbird-repair "$key_file"
[ -s "$key_file" ] || { echo "empty setup key on stdin" >&2; rm -f "$key_file"; exit 1; }

# --- unit ----------------------------------------------------------------
install -m 0644 "$SCRIPT_DIR/netbird-repair.service" "$UNIT"
systemctl daemon-reload
systemctl enable netbird-repair
systemctl restart netbird-repair

# --- enroll --------------------------------------------------------------
for i in $(seq 30); do
  $NB_CLI status --check live >/dev/null 2>&1 && break
  sleep 1
done
$NB_CLI up --setup-key-file "$key_file" --hostname "$NB_HOSTNAME" \
  --management-url "$MGMT" --wireguard-port "$WG_PORT"

for i in $(seq 30); do
  $NB_CLI status -d 2>/dev/null | grep -q 'Management: Connected' && break
  sleep 1
done
$NB_CLI status -d | grep -E '^(Daemon|Management|Signal|FQDN|NetBird IP)'
rm -f "$key_file"

echo "listeners:"
ss -ulpn | grep -E '51821|netbird' || true
systemctl is-enabled netbird-repair
