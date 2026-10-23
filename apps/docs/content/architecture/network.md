---
title: Network Allocation
---

# Network Allocation

## Multi-Site: One /16 per Site

Each site gets a single **`/16`** block. The second octet identifies the site; the rest of the address space is structured the same way at every site.

| Site    | CIDR            | Purpose             |
| ------- | --------------- | ------------------- |
| Olympus | `10.0.0.0/16`   | Primary (my home)   |
| Elysium | `10.1.0.0/16`   | Mom's site (future) |
| Arcadia | `10.2.0.0/16`   | Dad's site (future) |
| …       | `10.3.0.0/16` … | Additional sites    |

Within each /16, the same subnet layout is used (see [Olympus layout](#olympus-layout-1000016) below). For example: `10.0.1.0/24` = Olympus servers, `10.1.1.0/24` = Elysium servers. Site-to-site connectivity (e.g. Netbird overlay or VPN) is separate from this addressing.

### Proxmox clusters: per-site only

Proxmox clustering does **not** span WAN. Use one cluster per site: **Olympus**, **Elysium**, **Arcadia** each have their own Proxmox cluster. Cross-site “datacenter” clustering is not used; latency and split-brain risk over WAN make it unsuitable. Site-to-site links (Netbird, VPN) are for workload and management access, not Proxmox cluster membership.

## VMID Scheme

**Pattern:** `VMID = (3rd_octet × 1000) + last_octet`

VMIDs are **per-site**: each site’s Proxmox cluster has its own VMID namespace (so 10.0.1.3 at Olympus and 10.1.1.3 at Elysium can both be VMID 1003 on their respective hosts).

Examples (Olympus):

- `10.0.1.3` → VMID `1003`
- `10.0.3.1` → VMID `3001`
- `10.0.1.129` → VMID `1129`

## Olympus Layout (10.0.0.0/16)

CIDR allocation at the primary site. Other sites follow the same /24 roles with their own /16 (e.g. Elysium uses 10.1.0.0/24, 10.1.1.0/24, …).

### Olympus CIDR Overview

| Range           | Purpose                            |
| --------------- | ---------------------------------- |
| `10.0.0.0/24`   | Networking gear (router, switches) |
| `10.0.1.0/24`   | Server hardware                    |
| `10.0.2.0/24`   | IoT devices                        |
| `10.0.3.0/24`   | Trusted LAN clients                |
| `10.0.4.0/24`   | Trusted WLAN clients               |
| `10.0.5.0/24`   | HiFi/theater LAN                   |
| `10.0.6.0/24`   | HiFi/theater WLAN                  |
| `10.0.15.0/24`  | Guest WLAN                         |
| `10.0.128.0/17` | Reserved for Kubernetes VIPs       |

### Server Hardware (10.0.1.0/24)

### Workstation (10.0.1.1-7)

| IP       | VMID | Assignment               |
| -------- | ---- | ------------------------ |
| 10.0.1.1 | -    | Proxmox host             |
| 10.0.1.2 | 1002 | Storage LXC (NFS)        |
| 10.0.1.3 | 1003 | K3s VM                   |
| 10.0.1.4 | 1004 | NetBird VM (yggdrasil-olympus-1) |
| 10.0.1.5 | 1006 | Wings VM (game servers)  |
| 10.0.1.7 | -    | spare                    |

### Old Server (10.0.1.8-15)

| IP           | VMID | Assignment   |
| ------------ | ---- | ------------ |
| 10.0.1.8     | -    | Proxmox host |
| 10.0.1.9     | 1009 | K3s VM       |
| 10.0.1.10-15 | -    | spare        |

### Reserved Ranges

| Range          | Purpose                  |
| -------------- | ------------------------ |
| 10.0.1.16-127  | Future powerful hardware |
| 10.0.1.128-255 | Mini-PCs                 |

### Mini-PC Allocation Pattern

| IP             | VMID | Assignment                   |
| -------------- | ---- | ---------------------------- |
| 10.0.1.128     | -    | echo-olympus-1 (Proxmox host) |
| 10.0.1.129     | 1129 | hydra-olympus-echo-1 (K3s VM) |
| 10.0.1.130-131 | -    | echo-olympus-1 reserved       |
| 10.0.1.132     | -    | echo-olympus-2 (Proxmox host) |
| 10.0.1.133     | 1133 | hydra-olympus-echo-2 (K3s VM) |
| ...            | ...  | ...                          |

## Trusted LAN Clients (10.0.3.0/24)

| IP       | VMID | Assignment                      |
| -------- | ---- | ------------------------------- |
| 10.0.3.1 | 3001 | Workstation VM (Gaming/Blender) |

## Kubernetes VIPs (10.0.128.0/24)

| IP            | Purpose                                        |
| ------------- | ---------------------------------------------- |
| 10.0.128.1    | Control plane API (kube-vip)                   |
| 10.0.128.2    | Traefik/Ingress (router forwards 80/443 here)  |
| 10.0.128.3    | CoreDNS LoadBalancer (legacy exposure)         |
| 10.0.128.4    | qBittorrent BitTorrent ports                   |
| 10.0.128.5    | ms365-mcp private endpoint (Hermes)            |
| 10.0.128.6    | tastebase-db Postgres LAN endpoint             |
| 10.0.128.7-60 | Future LoadBalancer services                   |

## Proxmox Network Bridges

| Bridge | NIC    | Purpose                            |
| ------ | ------ | ---------------------------------- |
| vmbr0  | 2.5GbE | Proxmox management, Workstation VM |
| vmbr1  | 10GbE  | K3s VM, high-speed storage         |
