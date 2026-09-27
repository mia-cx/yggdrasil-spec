#!/usr/bin/env bash
# Install the pinned NetBird client on a K3s node and enroll it with a
# k3s-nodes setup key. Usage: sudo ./install-netbird-client.sh <setup-key-file>
set -euo pipefail

NETBIRD_VERSION=0.79.0
MANAGEMENT_URL=https://netbird.mia.cx
KEYRING=/usr/share/keyrings/netbird-archive-keyring.gpg

key_file=${1:?usage: install-netbird-client.sh <setup-key-file>}
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }

# Without a host iptables binary, NetBird writes -i wt0 rules into the
# iptables-nft ip filter table that k3s's bundled iptables cannot parse,
# crash-looping the embedded kube-router netpol controller (cmp sreg undef).
command -v iptables >/dev/null || { echo "no host iptables; refusing to run (see README known issue)" >&2; exit 1; }

# A wt0 without a running netbird service is a leftover from the removed host-network pods.
if ip link show wt0 &>/dev/null && ! systemctl is-active --quiet netbird; then
  echo "wt0 exists but no netbird service owns it; remove the leftover first" >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl gnupg
curl -fsSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor --yes -o "$KEYRING"
echo "deb [signed-by=$KEYRING] https://pkgs.netbird.io/debian stable main" >/etc/apt/sources.list.d/netbird.list
apt-get update
apt-get install -y --allow-downgrades "netbird=$NETBIRD_VERSION"
apt-mark hold netbird

systemctl is-enabled --quiet netbird || netbird service install
systemctl enable --now netbird

# --disable-dns leaves host resolution untouched; --disable-client-routes keeps
# node routing independent of any mesh routes.
netbird up --management-url "$MANAGEMENT_URL" --setup-key-file "$key_file" \
  --hostname "$(hostname)" --disable-dns --disable-client-routes
netbird status
