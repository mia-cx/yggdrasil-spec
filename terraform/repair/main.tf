# yggdrasil-repair-1: independent Repair mesh plus the primary mesh's
# relay/STUN on one Hetzner VPS. Stack files live in
# hosts/yggdrasil-repair-1/ and are embedded into cloud-init user_data.
# Providers authenticate via HCLOUD_TOKEN and CLOUDFLARE_API_TOKEN env vars
# only.

provider "hcloud" {}

provider "cloudflare" {}

resource "hcloud_ssh_key" "mia" {
  name       = "mia@Iris.local"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGygei6nTgxgiH63NRY5h02BZTK/85XX2kCBhlbTBm6R"
}

resource "hcloud_primary_ip" "ipv4" {
  name              = "yggdrasil-repair-1-ipv4"
  type              = "ipv4"
  location          = "nbg1"
  auto_delete       = false
  delete_protection = true

  # The IPs must survive the server: never destroy them via tofu.
  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_primary_ip" "ipv6" {
  name              = "yggdrasil-repair-1-ipv6"
  type              = "ipv6"
  location          = "nbg1"
  auto_delete       = false
  delete_protection = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "hcloud_firewall" "repair" {
  name = "yggdrasil-repair-1"

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "SSH"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "HTTP: ACME HTTP-01 and HTTPS redirect"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "HTTPS: Traefik websecure"
  }

  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "3478"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Repair mesh embedded STUN"
  }

  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "3479"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Primary mesh relay STUN"
  }

  rule {
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "ICMP (ping)"
  }
}

resource "hcloud_server" "repair" {
  name         = "yggdrasil-repair-1"
  server_type  = "cx23"
  image        = "debian-13"
  location     = "nbg1"
  ssh_keys     = [hcloud_ssh_key.mia.id]
  firewall_ids = [hcloud_firewall.repair.id]

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.ipv4.id
    ipv6_enabled = true
    ipv6         = hcloud_primary_ip.ipv6.id
  }

  user_data = templatefile("${path.module}/../../hosts/yggdrasil-repair-1/user-data.yaml.tftpl", {
    compose_yaml     = file("${path.module}/../../hosts/yggdrasil-repair-1/compose.yaml")
    traefik_yaml     = file("${path.module}/../../hosts/yggdrasil-repair-1/traefik.yaml")
    dynamic_yaml     = file("${path.module}/../../hosts/yggdrasil-repair-1/dynamic.yaml")
    config_yaml_tmpl = file("${path.module}/../../hosts/yggdrasil-repair-1/config.yaml.tmpl")
    dashboard_env    = file("${path.module}/../../hosts/yggdrasil-repair-1/dashboard.env")
    env_example      = file("${path.module}/../../hosts/yggdrasil-repair-1/.env.example")
    bootstrap_sh     = file("${path.module}/../../hosts/yggdrasil-repair-1/repair-bootstrap.sh")
  })

  lifecycle {
    # Editing stack files must never silently rebuild a stateful server.
    # A rebuild is explicit: tofu apply -replace=hcloud_server.repair
    ignore_changes = [user_data]
  }
}

data "cloudflare_zone" "mia_cx" {
  filter = {
    name = "mia.cx"
  }
}

resource "cloudflare_dns_record" "netbird_repair_a" {
  zone_id = data.cloudflare_zone.mia_cx.id
  name    = "netbird-repair.mia.cx"
  type    = "A"
  content = hcloud_primary_ip.ipv4.ip_address
  proxied = false
  ttl     = 1
  comment = "yggdrasil-repair-1 (terraform/repair)"
}

resource "cloudflare_dns_record" "netbird_repair_aaaa" {
  zone_id = data.cloudflare_zone.mia_cx.id
  name    = "netbird-repair.mia.cx"
  type    = "AAAA"
  content = cidrhost(hcloud_primary_ip.ipv6.ip_network, 1)
  proxied = false
  ttl     = 1
  comment = "yggdrasil-repair-1 (terraform/repair)"
}

resource "cloudflare_dns_record" "netbird_relay_a" {
  zone_id = data.cloudflare_zone.mia_cx.id
  name    = "netbird-relay.mia.cx"
  type    = "A"
  content = hcloud_primary_ip.ipv4.ip_address
  proxied = false
  ttl     = 1
  comment = "yggdrasil-repair-1 (terraform/repair)"
}

resource "cloudflare_dns_record" "netbird_relay_aaaa" {
  zone_id = data.cloudflare_zone.mia_cx.id
  name    = "netbird-relay.mia.cx"
  type    = "AAAA"
  content = cidrhost(hcloud_primary_ip.ipv6.ip_network, 1)
  proxied = false
  ttl     = 1
  comment = "yggdrasil-repair-1 (terraform/repair)"
}
