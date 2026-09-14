# VPS options for Yggdrasil NetBird recovery

Retrieved 2026-09-14. Prices and product availability can change; confirm the final cart before ordering.

## Workload and sizing

NetBird's combined self-hosted server (Management, Signal, Relay and STUN) requires at least 1 vCPU and 2 GB RAM, plus public TCP 80/443 and UDP 3478 ([NetBird quickstart](https://docs.netbird.io/selfhosted/selfhosted-quickstart)). For Yggdrasil, 2 vCPU and 4 GB RAM is the sensible floor: it leaves room for an independent secondary NetBird repair mesh, monitoring, and relay traffic without making the smallest supported configuration the recovery ceiling.

The repair mesh is a separate NetBird network with its own Management state. It does not replicate or promote the home-primary network, which avoids shared-state fencing and split brain. Repair devices keep profiles for both networks and manually switch to the repair profile during an incident; NetBird currently permits multiple profiles but activates only one at a time ([NetBird profiles](https://docs.netbird.io/client/profiles)).

## Advertised options

| Provider and plan | Advertised resources | Network and transfer | Location | Advertised monthly price |
|---|---|---|---|---|
| **OVHcloud VPS-1** | 2 vCores, 4 GB RAM, 40 GB NVMe, daily one-day backup | 500 Mbps; unlimited traffic; dedicated IPv4 and IPv6 included | Choose a European site; Germany is offered | **€3.81 ex. VAT / €4.61 incl. Dutch VAT** |
| **Hetzner CX23** | 2 shared x86 vCPU, 4 GB RAM, 40 GB NVMe | At least 20 TB/month in EU; IPv6 free; primary IPv4 €0.50/month ex. VAT | Falkenstein or Nuremberg, Germany; Helsinki also offered | €6.53 incl. 19% VAT excluding IPv4; about **€7.24 incl. 21% Dutch VAT and IPv4** |
| **netcup VPS 500 G12** | 2 shared x86 vCore, 4 GB ECC RAM, 128 GB NVMe | “Traffic included” without a quantity on the current product page; static IPv4 plus /64 IPv6 available; UDP firewall rules supported | Amsterdam, Nuremberg or Vienna | €5.91 shown incl. 19% VAT; price varies with residence (about **€6.01 at 21% VAT**) |
| **Scaleway DEV1-S** | 2 vCPU, 2 GB RAM; storage is extra | 200 Mbps; egress and IPv6 included; attached IPv4 and storage extra; UDP security-group rules supported | Amsterdam available | About €6.55/month for compute, before storage and IPv4 |

Sources: [OVHcloud Netherlands pricing and transfer terms](https://www.ovhcloud.com/nl/vps/unmetered-vps/), [OVHcloud included IPv4/IPv6](https://www.ovhcloud.com/de/vps/vps-ip/), [OVHcloud Germany availability](https://www.ovhcloud.com/en-gb/vps/vps-deutschland/), [Hetzner June 2026 prices](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/), [Hetzner CX resources and EU traffic](https://www.hetzner.com/cloud/cost-optimized/), [Hetzner IP pricing](https://docs.hetzner.com/cloud/servers/primary-ips/overview/), [netcup VPS pricing and locations](https://www.netcup.com/en/server/vps), [netcup address options](https://www.netcup.com/en/helpcenter/documentation/server/network-configuration), [netcup UDP firewall behavior](https://www.netcup.com/en/helpcenter/documentation/server/firewall), [Scaleway pricing](https://www.scaleway.com/en/pricing/virtual-instances/), [Scaleway locations](https://www.scaleway.com/en/choose-the-right-instance/), and [Scaleway UDP rules](https://www.scaleway.com/en/docs/instances/how-to/use-security-groups/).

The approximate Dutch totals for Hetzner and netcup are calculations from the providers' displayed German-VAT prices and published ex-VAT components. Checkout is authoritative.

## Infrastructure as code

Both leading candidates have first-party-supported Terraform/OpenTofu providers. Hetzner's `hcloud_server` supports creation, deletion, SSH keys, attached firewalls, stable Primary IPs and up to 32 KiB of cloud-init `user_data` ([server resource](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/server.html), [firewall resource](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/firewall), [Primary IP resource](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/primary_ip)). That is enough to provision the machine and bootstrap the repair stack from this repository in one OpenTofu workflow.

OVHcloud's `ovh_vps` can order a VPS, choose its OS and install a public SSH key; its provider can also manage IP firewall rules ([VPS resource](https://registry.terraform.io/providers/ovh/ovh/latest/docs/resources/vps), [firewall resource](https://registry.terraform.io/providers/ovh/ovh/latest/docs/resources/ip_firewall_rule)). The VPS resource does not expose cloud-init or general `user_data`, so a second configuration mechanism is still needed after provisioning.

## Judgment

**Choose Hetzner CX23 in Falkenstein or Nuremberg as the primary recommendation when repository-driven provisioning is the priority.** It clears the practical 2-vCPU/4-GB floor, and its provider covers the server, stable addresses, firewall and cloud-init bootstrap. Its approximate Dutch total is €7.24/month with IPv4. The 20 TB monthly allowance is ample for control-plane and recovery traffic and likely enough for occasional relayed media.

OVHcloud VPS-1 is the **bandwidth-heavy alternative** at €4.61/month including Dutch VAT. Its 500 Mbps unmetered link, included addresses and daily one-day backup are unusually strong at this price. Choose it if Relay transfer matters more than a single-tool bootstrap; the server and firewall can still be ordered through OpenTofu, but configuring the operating system needs a second step. OVHcloud VPS-2 raises capacity to 4 vCores, 8 GB RAM, 75 GB NVMe and 1 Gbps for €8.72/month including Dutch VAT.

For scale, one continuous 20 Mbps stream transfers roughly 6.5 TB in a 30-day month, so Hetzner's 20 TB is about three such streams continuously before overhead. That is generous for fallback traffic but not unlimited; alert on transfer use.

netcup offers the most storage and an Amsterdam location at a low price, but its public product page does not quantify “Traffic included.” That prevents certifying it for bandwidth-heavy Jellyfin relay duty before purchase. It remains a good control-plane candidate if netcup confirms the allowance and port speed in the cart or in writing.

Scaleway is geographically attractive and does not bill egress, but its 2 GB plan sits exactly at NetBird's minimum and excludes both storage and IPv4 from the displayed price. It is less capacity for more money once the required extras are added.

Whichever provider is chosen, expose only TCP 80/443, UDP 3478, and tightly restricted administration. Test direct peer connectivity, forced Relay streaming, switching a restarted client to the repair profile, access while home NetBird/Hecate/K3s DNS are unavailable, and return to the home profile before treating the VPS as recovery infrastructure.
