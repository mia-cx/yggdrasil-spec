---
title: Network Allocation
---

# Network Allocation

## CIDR Overview

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

## VMID Scheme

**Pattern:** `VMID = (3rd_octet × 1000) + last_octet`

Examples:

- `10.0.1.3` → VMID `1003`
- `10.0.3.1` → VMID `3001`
- `10.0.1.129` → VMID `1129`

## Server Hardware (10.0.1.0/24)

### Workstation (10.0.1.1-7)

| IP       | VMID | Assignment               |
| -------- | ---- | ------------------------ |
| 10.0.1.1 | -    | Proxmox host             |
| 10.0.1.2 | 1002 | Storage LXC (NFS)        |
| 10.0.1.3 | 1003 | K3s VM                   |
| 10.0.1.4 | 1005 | Netbird LXC (management) |
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

| IP             | VMID | Assignment         |
| -------------- | ---- | ------------------ |
| 10.0.1.128     | -    | MPC-1 Proxmox host |
| 10.0.1.129     | 1129 | MPC-1 K3s VM       |
| 10.0.1.130-131 | -    | MPC-1 reserved     |
| 10.0.1.132     | -    | MPC-2 Proxmox host |
| 10.0.1.133     | 1133 | MPC-2 K3s VM       |
| ...            | ...  | ...                |

## Trusted LAN Clients (10.0.3.0/24)

| IP       | VMID | Assignment                      |
| -------- | ---- | ------------------------------- |
| 10.0.3.1 | 3001 | Workstation VM (Gaming/Blender) |

## Kubernetes VIPs (10.0.128.0/24)

| IP            | Purpose                                       |
| ------------- | --------------------------------------------- |
| 10.0.128.1    | Control plane API (kube-vip)                  |
| 10.0.128.2    | Traefik/Ingress (router forwards 80/443 here) |
| 10.0.128.3-60 | Future LoadBalancer services                  |

## Proxmox Network Bridges

| Bridge | NIC    | Purpose                            |
| ------ | ------ | ---------------------------------- |
| vmbr0  | 2.5GbE | Proxmox management, Workstation VM |
| vmbr1  | 10GbE  | K3s VM, high-speed storage         |
