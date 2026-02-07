---
title: Key Decisions
---

# Key Decisions

| Decision          | Choice                                     | Rationale                                      |
| ----------------- | ------------------------------------------ | ---------------------------------------------- |
| Naming            | Yggdrasil (Norse) + Greek deities          | World tree connects realms, devices are gods   |
| Domain            | yggdrasil.mia.cx                           | Subdomain of existing domain                   |
| Orchestration     | K3s                                        | Lightweight K8s, HA built-in                   |
| Identity Provider | Authentik LXC (10.0.1.3)                   | SSO for all services, independent of K3s       |
| Overlay network   | Netbird LXC (10.0.1.5) + exit nodes in K3s | Management independent, exit nodes distributed |
| Internal DNS      | Netbird DNS + CoreDNS                      | Split-horizon, internal-only resolution        |
| External fallback | Cloudflare Workers (Janus)                 | Friendly landing pages for non-Netbird users   |
| Floating VIPs     | kube-vip (ARP)                             | Single IP for router, auto-failover            |
| TLS certs         | cert-manager + Cloudflare DNS-01           | Wildcard certs, extractable                    |
| NFS server        | Storage LXC                                | Separation from host, lightweight (~1GB RAM)   |
| Media storage     | MergerFS in LXC                            | Mix disk sizes, easy replacement               |
| Critical storage  | NVMe (ext4 → ZFS)                          | Host manages filesystem, LXC exports via NFS   |
| K8s storage       | Longhorn (small) + NFS (bulk)              | Ceph overkill for 1GbE                         |
| PostgreSQL        | Shared instance, per-service DBs           | Lower overhead, unified backup                 |
| Redis             | Separate instance per service              | Prevent resource contention                    |
| Vaultwarden       | Isolated SQLite, no shared deps            | Root of trust, no circular dependencies        |

## Why LXC for Authentik & Netbird?

Both are deployed in **separate LXCs** rather than in K3s:

### Authentik LXC

- Stays up even if K3s is down
- Can authenticate to fix K3s issues
- Independent backup/restore

### Netbird LXC

- Management stays up even if K3s is down
- Existing WireGuard tunnels survive management outage
- Can still access infrastructure to fix K3s

### Exit Nodes in K3s

- Distributed across multiple nodes
- Benefits from K8s scheduling/redundancy
- Not critical if temporarily unavailable

## Why MergerFS over ZFS for HDDs?

- Mix different disk sizes (8TB → 22TB gradual upgrade)
- Simple JBOD with filesystem flexibility
- Lower RAM overhead than ZFS
- ZFS reserved for critical NVMe data (future RAIDZ1)

## Why Not TrueNAS?

- TrueNAS requires ZFS for everything
- MergerFS not available on TrueNAS
- Storage LXC provides same NFS functionality with less overhead
