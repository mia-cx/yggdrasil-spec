output "ipv4" {
  description = "Primary IPv4 address of yggdrasil-repair-1"
  value       = hcloud_primary_ip.ipv4.ip_address
}

output "ipv6" {
  description = "Primary IPv6 address of yggdrasil-repair-1 (first address of the /64)"
  value       = cidrhost(hcloud_primary_ip.ipv6.ip_network, 1)
}
