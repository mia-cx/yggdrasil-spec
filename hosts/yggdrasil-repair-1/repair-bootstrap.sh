#!/bin/sh
set -e
# Docker repo: key first, then the source list, then apt update. Order
# matters because the packages module may run before this script.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" > /etc/apt/sources.list.d/docker.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

cd /opt/netbird

# Generate .env only when absent: it holds the only secrets and must survive
# re-runs of this script (per-instance modules can re-run on rebuild).
if [ ! -f .env ]; then
  umask 077
  {
    echo "NETBIRD_ADMIN_EMAIL=repair-admin@mia.cx"
    echo "NETBIRD_ADMIN_PASSWORD=$(openssl rand -hex 24)"
    echo "NETBIRD_AUTH_SECRET=$(openssl rand -base64 32)"
    echo "NETBIRD_STORE_ENCRYPTION_KEY=$(openssl rand -base64 32)"
    echo "NB_SESSION_COOKIE_ENCRYPTION_KEY=$(openssl rand -base64 32)"
    echo "NETBIRD_RELAY_AUTH_SECRET=$(openssl rand -base64 32)"
  } > .env
  chmod 600 .env
fi

# Render config.yaml exactly like the README: .env is sourced as shell code,
# the bcrypt hash is derived at render time.
set -a
. ./.env
set +a
NETBIRD_ADMIN_PASSWORD_HASH=$(htpasswd -bnBC 12 "" "$NETBIRD_ADMIN_PASSWORD" | tr -d ':\n')
export NETBIRD_ADMIN_PASSWORD_HASH
envsubst < config.yaml.tmpl > config.yaml
chmod 600 config.yaml

docker compose up -d

touch /opt/netbird/.bootstrap-done
