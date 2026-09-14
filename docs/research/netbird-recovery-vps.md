# VPS options for Yggdrasil NetBird recovery

Retrieved 2026-09-14. Prices and product availability can change; confirm the final cart before ordering.

## Workload and sizing

NetBird's combined self-hosted server (Management, Signal, Relay and STUN) requires at least 1 vCPU and 2 GB RAM, plus public TCP 80/443 and UDP 3478 ([NetBird quickstart](https://docs.netbird.io/selfhosted/selfhosted-quickstart)). For Yggdrasil, 2 vCPU and 4 GB RAM is the sensible floor: it leaves room for the independent WireGuard recovery endpoint, monitoring, and an inactive recovery Management surface without making the smallest supported configuration the recovery ceiling.

The WireGuard keepalive tunnel supplies an independent repair path. It does **not** synchronize NetBird Management state or fence concurrent writers. A VPS recovery copy must be passive, receive tested state backups or replication, and be promoted under a single-writer fencing procedure. It is not a community-edition active-active pair.

## Advertised options

| Provider and plan | Advertised resources | Network and transfer | Location | Advertised monthly price |
|---|---|---|---|---|
| **OVHcloud VPS-1** | 2 vCores, 4 GB RAM, 40 GB NVMe, daily one-day backup | 500 Mbps; unlimited traffic; dedicated IPv4 and IPv6 included | Choose a European site; Germany is offered | **€3.81 ex. VAT / €4.61 incl. Dutch VAT** |
| **Hetzner CX23** | 2 shared x86 vCPU, 4 GB RAM, 40 GB NVMe | At least 20 TB/month in EU; IPv6 free; primary IPv4 €0.50/month ex. VAT | Falkenstein or Nuremberg, Germany; Helsinki also offered | €6.53 incl. 19% VAT excluding IPv4; about **€7.24 incl. 21% Dutch VAT and IPv4** |
| **netcup VPS 500 G12** | 2 shared x86 vCore, 4 GB ECC RAM, 128 GB NVMe | “Traffic included” without a quantity on the current product page; static IPv4 plus /64 IPv6 available; UDP firewall rules supported | Amsterdam, Nuremberg or Vienna | €5.91 shown incl. 19% VAT; price varies with residence (about **€6.01 at 21% VAT**) |
| **Scaleway DEV1-S** | 2 vCPU, 2 GB RAM; storage is extra | 200 Mbps; egress and IPv6 included; attached IPv4 and storage extra; UDP security-group rules supported | Amsterdam available | About €6.55/month for compute, before storage and IPv4 |

Sources: [OVHcloud Netherlands pricing and transfer terms](https://www.ovhcloud.com/nl/vps/unmetered-vps/), [OVHcloud included IPv4/IPv6](https://www.ovhcloud.com/de/vps/vps-ip/), [OVHcloud Germany availability](https://www.ovhcloud.com/en-gb/vps/vps-deutschland/), [Hetzner June 2026 prices](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/), [Hetzner CX resources and EU traffic](https://www.hetzner.com/cloud/cost-optimized/), [Hetzner IP pricing](https://docs.hetzner.com/cloud/servers/primary-ips/overview/), [netcup VPS pricing and locations](https://www.netcup.com/en/server/vps), [netcup address options](https://www.netcup.com/en/helpcenter/documentation/server/network-configuration), [netcup UDP firewall behavior](https://www.netcup.com/en/helpcenter/documentation/server/firewall), [Scaleway pricing](https://www.scaleway.com/en/pricing/virtual-instances/), [Scaleway locations](https://www.scaleway.com/en/choose-the-right-instance/), and [Scaleway UDP rules](https://www.scaleway.com/en/docs/instances/how-to/use-security-groups/).

The approximate Dutch totals for Hetzner and netcup are calculations from the providers' displayed German-VAT prices and published ex-VAT components. Checkout is authoritative.

## Judgment

**Choose OVHcloud VPS-1 in Germany as the primary recommendation.** It clears the practical 2-vCPU/4-GB floor, includes both public address families and a small daily recovery point, and costs €4.61/month for a Dutch customer. Its 500 Mbps unmetered link is unusually well matched to a public Relay: OVHcloud explicitly describes the European offer as suitable for VPNs, proxies, streaming, and sustained high transfer. It is enough for possible relayed Jellyfin use; the home uplink and Jellyfin server will probably become the limit first.

OVHcloud VPS-2 is the **bandwidth-heavy alternative** at €8.72/month including Dutch VAT: 4 vCores, 8 GB RAM, 75 GB NVMe, 1 Gbps and unlimited traffic. Buy it only if measurements show many simultaneous relayed streams, or if the promoted recovery Management stack needs more memory. Starting with VPS-1 is low risk because OVHcloud advertises in-place resource upgrades.

Hetzner CX23 is the strongest metered alternative. Its 20 TB allowance is ample for control-plane and recovery traffic and likely enough for occasional relayed media. For scale, one continuous 20 Mbps stream transfers roughly 6.5 TB in a 30-day month, so 20 TB is about three such streams continuously before overhead. That is generous for fallback traffic but not unlimited; alert on transfer use.

netcup offers the most storage and an Amsterdam location at a low price, but its public product page does not quantify “Traffic included.” That prevents certifying it for bandwidth-heavy Jellyfin relay duty before purchase. It remains a good control-plane candidate if netcup confirms the allowance and port speed in the cart or in writing.

Scaleway is geographically attractive and does not bill egress, but its 2 GB plan sits exactly at NetBird's minimum and excludes both storage and IPv4 from the displayed price. It is less capacity for more money once the required extras are added.

Whichever provider is chosen, expose only TCP 80/443, UDP 3478, the chosen WireGuard UDP port, and tightly restricted administration. Test direct peer connectivity, forced Relay streaming, recovery-tunnel access, state restoration, promotion fencing, and return to the home primary before treating the VPS as failover infrastructure.
