---
title: Resilience Nodes (Hosted DR)
---

# Resilience Nodes Roadmap

This is an earlier proposal, not the selected first-site recovery architecture. See [Multi-site resilience](./multi-site-resilience.md) for current discussion of cluster boundaries and storage. The [NetBird Wayfinder map](https://github.com/mia-cx/yggdrasil-spec/issues/5) holds the accepted first-site decisions; cross-site K3s quorum and overlay-VIP behavior remain unproven here.

A small number of **hosted nodes** (outside the homelab) that keep the Kubernetes cluster and GitOps configs available when the homelab is down. No PVC data is replicated to these nodes — **configs only**, so they stay slim and cheap.

## Goal

- **When homelab is up:** Cluster includes both homelab nodes and 1–2 hosted “resilience” nodes. Control plane and Argo CD (or Flux) can run there; workloads that need Longhorn or NFS stay on homelab nodes.
- **When homelab is down:** Resilience nodes keep the cluster API and GitOps alive. When the homelab comes back, nodes rejoin and Argo CD reapplies configs from git; no data lives on the hosted nodes.
- **Longhorn:** No PVC replicas on resilience nodes. Use Longhorn’s per-node “Disable Scheduling” (and eviction) so these nodes never hold storage — see [Keeping Longhorn off resilience nodes](#keeping-longhorn-off-resilience-nodes).

## What runs on resilience nodes

| Component                         | Purpose                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| K3s control plane (or agent only) | Cluster API available; optionally multi-master with one control-plane on hosted.                                                                                                                                                                                                                                                                        |
| Argo CD / Flux                    | GitOps: configs in git; when homelab nodes rejoin, apps reconcile from repo.                                                                                                                                                                                                                                                                            |
| Optional                          | Lightweight, stateless-only workloads (e.g. a tiny echo service). No Longhorn PVCs, no NFS.                                                                                                                                                                                                                                                             |
| **Netbird exit node** (optional)  | Same Linux peer can be a [routing peer](https://docs.netbird.io/how-to/configuring-default-routes-for-internet-traffic): route `0.0.0.0/0` (or selected traffic) through the resilience VPS so homelab or other Netbird clients tunnel out via that node’s public IP. Use case: self-hosted “VPN” (e.g. torrent or general traffic egress via the VPS). |

No databases, no media, no bulk data. Resilience = **cluster + configs**, not data replication. If you also use a resilience node as an exit node, the VPS provider is the one with the public IP and any abuse/complaints; see [Exit node use and VPS privacy](#exit-node-use-and-vps-privacy) below.

## Platform choice: AWS vs Azure vs VPS (OVH / Hetzner)

| Option                                                                  | Pros                                                                                   | Cons                                                                                                              | Best for                                          |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| **Hetzner Cloud** ([docs](https://docs.hetzner.com/cloud/))             | Very cheap (e.g. CX22: 2 vCPU, 4 GB RAM, ~€4/mo). Simple VPS, run K3s yourself. EU/US. | You manage OS and K3s; no managed K8s.                                                                            | **Recommended for “slim + cheap, configs only.”** |
| **OVH Public Cloud** ([docs](https://docs.ovh.com/gb/en/public-cloud/)) | Similar to Hetzner; flexible sizes; EU.                                                | Slightly more dashboard complexity.                                                                               | Good EU alternative.                              |
| **AWS (EC2)**                                                           | Integrates with Route53, IAM, VPC.                                                     | More expensive for small always-on VMs; egress costs. Managed options (EKS) don’t match “join existing K3s” well. | If you already standardize on AWS.                |
| **Azure (VMs)**                                                         | Similar to AWS; good if you’re in Azure ecosystem.                                     | Same cost/complexity trade-off as AWS.                                                                            | If you already use Azure.                         |

**Recommendation:** For a **small number of cheap nodes that only run control plane + GitOps**, **Hetzner or OVH VPS** is usually the best fit: small instances (e.g. 2 vCPU, 4 GB RAM), install K3s, join to the existing cluster via Netbird or a VPN so the API server is reachable. AWS/Azure make more sense if you need tight integration (DNS, secrets, compliance) or already run there.

### Exit node use and VPS privacy

If you use a resilience node as a **Netbird exit node** (e.g. to tunnel torrent or other traffic through the VPS), that traffic egresses from the **VPS provider’s IP**. Abuse or copyright complaints typically go to the provider. Choose a host whose **acceptable use policy**, **privacy policy**, and **jurisdiction** match your expectations.

| Type                        | Examples                                                                          | Notes                                                                                                                                                                                            |
| --------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Standard EU (cheap)**     | Hetzner, OVH                                                                      | Clear abuse/DMCA processes; they forward notices and may require response. Fine for many uses; not “no-log” or abuse-agnostic.                                                                   |
| **Privacy-focused**         | [PrivateAlps](https://privatealps.net/) (CH), [Njalla](https://njal.la/) (varied) | No-log or minimal-log policies, crypto payment options, jurisdictions often cited for privacy. Read their AUP and abuse handling.                                                                |
| **Netherlands**             | Various NL hosts                                                                  | Enforcement on downloading/usenet is often minimal or unenforced. Practical option for NL residents; middle ground between standard EU and full offshore.                                        |
| **Offshore / DMCA-ignored** | Various (e.g. NL, Romania)                                                        | Providers that market “DMCA-ignored” or offshore; often crypto-only, no KYC. Quality and longevity vary; check reviews and AUP.                                                                  |
| **Abuse-resistant**         | [Aeza](https://aeza.net/) (Russia)                                                | Russia-based; OFAC-sanctioned (US, 2025), so not subject to US pressure. Often chosen for exit/torrent; AUP not prominent. **US persons cannot legally transact with OFAC-designated entities.** |

Do your own due diligence: read the AUP, see how they handle abuse/DMCA, and whether they log or share data. For exit-node + torrent use, many people prefer a provider that accepts crypto, has a strict no-log policy, and operates in a jurisdiction with strong privacy or that does not routinely act on copyright notices.

### Sizing (resilience only)

- **1 node:** Minimal: one small VPS runs K3s server (or agent + Argo CD). Single point of failure for “resilience” but keeps configs and API alive.
- **2 nodes:** Better: two small VPS in different AZs (if provider supports it), both join the cluster; control plane can be HA if you promote one to server. Still no storage on these nodes.

## Keeping Longhorn off resilience nodes

Resilience nodes **must not** hold any Longhorn replicas — only homelab nodes should store PVC data. Two ways to enforce that:

1. **Longhorn UI (recommended):** After each resilience node joins the cluster, in [Longhorn](https://longhorn.io/docs/1.10.0/nodes-and-volumes/nodes/scheduling/) go to **Node** → select the node → **Edit Node** → set **Scheduling** to **Disable**. Optionally set **Eviction Requested** to `true` once so any replica that landed there is moved off (see [Evicting Replicas](https://longhorn.io/docs/1.10.0/nodes-and-volumes/nodes/disks-or-nodes-eviction/)). No new replicas will be placed on that node.
2. **Kubernetes cordon:** Cordoned nodes are excluded by Longhorn when the global setting **Disable Scheduling On Cordoned Node** is `true` (default). Cordon, however, also prevents **all** workload scheduling on that node — so you would not be able to run Argo CD or control plane there. Prefer (1) so resilience nodes can run pods but not storage.

Label resilience nodes (e.g. `topology.kubernetes.io/zone=resilience` or `node-type=resilience`) so you can target them in Longhorn and in [Workload Placement](../../infrastructure/workload-placement.md) (e.g. avoid scheduling data-heavy workloads there via affinity).

## Security: VPS as trust boundary

A resilience VPS that runs Netbird (and optionally K3s) is a **new attack surface**: the provider, or anyone who compromises the host, could abuse the Netbird client or SSH access to reach your overlay and cluster. Harden accordingly:

- **SSH:** Key-only auth; no password logins. Restrict `AuthorizedKeysFile` to a small set of keys you control. Consider a separate key per resilience node or role.
- **Users:** Minimal local accounts; no shared or weak passwords. Use a single admin user (or role account) with sudo only where needed.
- **Secrets:** Netbird setup keys, K3s join tokens, and kubeconfig live on the box; treat the VPS as hostile to those secrets if the host or provider is compromised. Rotate join tokens and review Netbird peer list if you ever suspect compromise.
- **Netbird / K8s:** Use Netbird groups and ACLs so the resilience peer can only reach what it needs (e.g. control plane, not every service). Limit which workloads run on resilience nodes (node affinity / taints).
- **Disk encryption:** Encrypting the root partition (e.g. LUKS) protects secrets at rest if the provider or someone gets disk access. Check whether the host supports it: **provider-managed encrypted volumes** (they hold the key, unlock at boot — protects against physical disk theft, not the provider), or **custom ISO + LUKS** (you set a passphrase or keyfile; unattended reboot then requires key injection or a key fetched at boot, e.g. from your infra). If you use a passphrase only, you must have console access at every reboot. Confirm with the provider (e.g. Aeza) if they offer encrypted disks or custom ISO so you can install with LUKS.

When you add a resilience node, treat it as untrusted infrastructure that holds just enough to keep cluster + configs alive and (optionally) act as an exit node — not as part of your most trusted LAN.

## Networking: how resilience (and cross-site) nodes join the cluster

Cross-site and hosted nodes can only join if they can reach the cluster API. You have two options:

| Approach                  | Description                                                                                                                                                                                                                                           | Recommendation                       |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| **Overlay on every node** | Run a Netbird (or Tailscale/WireGuard) client on **each** K3s VM and each hosted node. They all get IPs on the same private overlay; the API is reachable at the control plane’s overlay IP (or kube-vip if it’s on the overlay). No public exposure. | **Preferred.**                       |
| **Expose API publicly**   | Put the K3s API behind a LB/tunnel and open it to the internet. You still need auth and tight lock-down. Bigger attack surface.                                                                                                                       | Avoid unless you have no other path. |

**Best approach: Netbird (or overlay) on each node that must see the cluster.**

- **Homelab K3s VMs:** Run the Netbird client inside each K3s VM (or on the host that runs the VM, with routing so the VM can use the overlay). Then control plane and agents all talk over the overlay as well as LAN.
- **Resilience / hosted VPS:** Install Netbird on the VPS, join the same mesh → it gets an overlay IP and can reach the control plane.
- **Future cross-site nodes (e.g. mini-PCs elsewhere):** Same pattern: Netbird on the node → overlay IP → join using the control plane’s overlay address.

The cluster API stays **private**; nothing is exposed on the public internet. Every node that needs to join or talk to the API is simply on the same overlay.

**Netbird overlay IP for a stable join URL:** Netbird assigns each peer an overlay IP from 100.64.0.0/10; the same peer normally keeps the same IP across reconnects (tied to peer ID). For **explicit static reservation** you can set a peer’s IP via the API: **PUT** `/api/peers/{peerId}` with body `{"ip": "100.64.x.x", ...}` (see [Peers API](https://docs.netbird.io/ipa/resources/peers)); the peer may need a restart to apply the new IP. Alternatively, use **Netbird DNS**: each peer gets a stable name (e.g. `hostname.netbird.cloud`), so you can join with `--server https://<control-plane-peer-name>:6443` and resolve via Netbird’s DNS instead of a fixed overlay IP.

**kube-vip nuance:** If the API VIP (e.g. 10.0.128.1) is only advertised on the LAN, nodes that are _only_ on the overlay (e.g. a resilience VPS) won’t see the VIP. In that case, join using the **control plane node’s overlay IP** directly, e.g. `--server https://100.64.0.x:6443`.

**Can kube-vip advertise two VIPs (LAN + overlay) for the same API?** The control plane static pod supports **one** `address` and **one** `vip_interface` — no built-in "second VIP on second interface" for a single pod. Options: **(1)** Use the control plane overlay IP for join (no second VIP). **(2)** Add a **LoadBalancer Service** that targets the API server with `kube-vip.io/loadbalancerIPs: "<overlay-IP>"` and `kube-vip.io/serviceInterface: "netbird0"`; kube-vip service watcher will then advertise that IP on the overlay so you have 10.0.128.1 (static pod) and the overlay IP (Service). **(3)** Run a second kube-vip process for the overlay VIP (possible but two static pods / lease behaviour to validate). Prefer (1) for simplicity; use (2) if you want a stable overlay VIP for join.

## Scope and out of scope

- **In scope:** Choosing platform (VPS vs cloud), sizing, joining resilience nodes to Hydra, excluding them from Longhorn scheduling, what runs there (control plane + GitOps), and naming (add to [Naming](../../architecture/naming.md) when you deploy).
- **Out of scope:** Full DR failover of stateful apps (that would require backups/restore and possibly a separate “recovery” cluster). This roadmap is “keep cluster and configs alive,” not “replicate data to the cloud.”

## When you add resilience nodes

1. Provision 1–2 small VMs (Hetzner/OVH or AWS/Azure).
2. Install K3s (server or agent) and join to the cluster via Netbird/overlay (or exposed API).
3. In Longhorn: for each resilience node, **Disable Scheduling** (and evict if needed). Confirm no PVC replicas on those nodes.
4. Add the node(s) to the [Naming](../../architecture/naming.md) table with a consistent name (e.g. `hydra-<provider>-resilience-1`).
5. Optionally add a node label (e.g. `node-type=resilience`) and use it in workload placement so data-heavy workloads never schedule there.

## Quick links

| Resource                          | Link                                                                                                         |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Longhorn node scheduling          | [Scheduling](https://longhorn.io/docs/1.10.0/nodes-and-volumes/nodes/scheduling/)                            |
| Longhorn eviction                 | [Evicting Replicas](https://longhorn.io/docs/1.10.0/nodes-and-volumes/nodes/disks-or-nodes-eviction/)        |
| Hetzner Cloud                     | [docs](https://docs.hetzner.com/cloud/)                                                                      |
| OVH Public Cloud                  | [docs](https://docs.ovh.com/gb/en/public-cloud/)                                                             |
| Workload placement (this repo)    | [Workload Placement](../../infrastructure/workload-placement.md)                                             |
| Naming (this repo)                | [Naming](../../architecture/naming.md)                                                                       |
| Netbird Peers API (set peer IP)   | [Peers](https://docs.netbird.io/ipa/resources/peers)                                                         |
| Netbird DNS                       | [DNS](https://docs.netbird.io/manage/dns)                                                                    |
| Netbird exit node (default route) | [Configuring default routes](https://docs.netbird.io/how-to/configuring-default-routes-for-internet-traffic) |
