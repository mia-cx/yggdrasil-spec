---
title: Node Onboarding Roadmap
---

# Node Onboarding Roadmap (PXE + IaC)

A **documentation plan** for making "add a new mini-PC and join it to the cluster" trivial: PXE netboot, cloud-init for first-boot configuration, and OpenTofu for node and network provisioning.

## Goal

- **Today:** Adding a mini-PC means manual install (USB/netinst), hostname, SSH, K3s join, labels, DNS/DHCP by hand.
- **Target:** Plug in a new mini-PC on the LAN, set it to PXE boot → it netboots a cloud-init image → first boot applies node identity (hostname, SSH, K3s join token, optional Netbird) → OpenTofu already defines (or is updated once with) DHCP reservation, DNS, and any Proxmox/VM wiring so the node is fully wired and joinable.

## Architecture: Mini-PC = Proxmox Node + K3s VM

Each mini-PC is a **Proxmox node** (bare metal runs Proxmox only). It does **not** run K3s directly on metal; instead, each mini-PC hosts **one K3s VM** that joins the Hydra cluster.

| Layer         | Hostname pattern      | Example              | Purpose                    |
| ------------- | --------------------- | -------------------- | -------------------------- |
| Bare metal    | `echo-<site>-X`        | echo-olympus-1        | Proxmox node identity      |
| VM on that PC | `hydra-<site>-echo-X`  | hydra-olympus-echo-1  | K3s node (join to cluster) |

All hostnames include the site (see [Naming](../../architecture/naming.md)); same pattern for other hosts (e.g. athena-olympus). Adding a new mini-PC: PXE-install Proxmox as **echo-&lt;site&gt;-X**, then create one VM **hydra-&lt;site&gt;-echo-X**. IP and VMID follow [Network](../../architecture/network.md) (e.g. 10.0.1.128 = echo-olympus-1 host, 10.0.1.129 = hydra-olympus-echo-1 VM).

## Scope

- **In scope:** PXE server and netboot image (for Proxmox install on mini-PCs), cloud-init image for the **K3s VM** (first-boot join and labels), OpenTofu for node inventory / DHCP / DNS and **Proxmox VM creation** (one K3s VM per mini-PC). Hostname automation: sequential **echo-&lt;site&gt;-X** and **hydra-&lt;site&gt;-echo-X** from a single list or count (site in every hostname).
- **Out of scope:** Detailed step-by-step runbooks (those live in [Runbooks](../../operations/runbooks.md)); migration phases stay in [Migration](../../operations/migration.md). Phase 6 (Mini-PCs) is the consumer of this workflow.

## Current State

- K3s control plane lives on a single VM (10.0.1.3, VMID 1003); see [Kubernetes (Hydra)](../../infrastructure/kubernetes.md).
- [Architecture](../../architecture/index.md) calls out future mini-PCs (16–32GB RAM, Intel N100/N305 for QuickSync).
- [Naming](../../architecture/naming.md) uses mythology theme (e.g. Hydra for cluster; new nodes need consistent hostnames).
- [Workload placement](../../infrastructure/workload-placement.md) defines node affinity (critical vs media); new nodes need labels.
- OpenTofu (see repo `AGENTS.md`) is set up for Cloudflare and (eventually) Proxmox; no node-level or DHCP/DNS IaC for bare-metal yet.

## 1. PXE Boot (Proxmox on the Mini-PC)

**Purpose:** New mini-PC hardware boots from the network and installs **Proxmox** with hostname **echo-&lt;site&gt;-X** (e.g. echo-olympus-1; no USB or manual ISO per box).

- **PXE server:** One host (e.g. primary Proxmox or a small VM/LXC) runs DHCP + TFTP + optional HTTP for boot files.
  - DHCP: Option 66 (TFTP server) and Option 67 (boot filename) so clients netboot.
  - TFTP: Provide `ipxe.efi` (or chain from vendor PXE to iPXE) and an iPXE script pointing to the Proxmox installer or a pre-baked image.
- **Netboot image:** Proxmox installer (netboot) or a **pre-baked image** that writes Proxmox to disk with hostname **echo-&lt;site&gt;-X** (injected from OpenTofu-generated config or DHCP). One image; site and X come from the node's identity (e.g. MAC → reservation → hostname).
- **Flow:** Mini-PC powers on → DHCP (gets IP and identity) → PXE → install Proxmox as **echo-&lt;site&gt;-X** → disk-boot Proxmox. The **K3s VM** on that host is created by OpenTofu (or Ansible) and gets its own first-boot via cloud-init (see §2).

**Decisions to document:** Where the PXE server runs, single-purpose Proxmox image vs generic installer, and how hostname echo-&lt;site&gt;-X is injected (config drive, script, or automated answer file).

## 2. Cloud-Init Image (K3s VM)

**Purpose:** First-boot configuration for the **K3s VM** (hydra-&lt;site&gt;-echo-X): hostname, SSH, K3s join, and node labels so it joins the cluster without manual steps.

- **Image:** A single cloud-init–ready image (e.g. Debian or Ubuntu minimal) used as the **VM template** for every hydra-&lt;site&gt;-echo-X:
  - `cloud-init` and `cloud-guest-utils` (or equivalent).
  - Default user + SSH; disabled password auth.
  - Optional: pre-installed K3s agent (not started) or one-time script to install and join.
- **Data source:** **NoCloud** (ISO or config drive) generated **per VM** by OpenTofu with `user-data` and `meta-data` so each VM gets the correct hostname (e.g. hydra-olympus-echo-1) and join token.
- **user-data:** Hostname `hydra-<site>-echo-X`, SSH keys, one-time install and join K3s (agent), optional Netbird, then apply node labels (e.g. `workloads/media`). Token from config drive or a small token endpoint.
- **meta-data:** `instance-id` and `local-hostname` (hydra-&lt;site&gt;-echo-X) for idempotency and correct hostname.

**Decisions to document:** Base image (Debian vs Ubuntu), who builds the template (Packer vs debootstrap), and how K3s join tokens are issued (per-VM config drive vs token server).

## 3. OpenTofu (IaC) and Hostname Automation

**Purpose:** Node inventory, network identity, and **Proxmox VM creation** so "add a node" is a single code change (add one entry) and apply; hostnames **echo-&lt;site&gt;-X** and **hydra-&lt;site&gt;-echo-X** are derived automatically so you never hand-type the next number.

### Auto-incrementing hostnames

- **echo-&lt;site&gt;-X (Proxmox host):** Maintain a list or count per site in OpenTofu (e.g. `echo_nodes = [1, 2, 3]` and `site = "olympus"`). Hostname is `echo-${site}-${each.value}` or `echo-${site}-${count.index + 1}`. **Adding a new mini-PC = appending to the list or incrementing the count**; the next index is automatic. PXE receives this hostname from the same source (e.g. generated config or DHCP identity).
- **hydra-&lt;site&gt;-echo-X (K3s VM):** Same list or count drives the VM: for each Echo node, OpenTofu creates **one Proxmox VM** with name/hostname `hydra-<site>-echo-${X}` (e.g. `hydra-olympus-echo-1`). Site is a variable (e.g. `olympus`) so all VMs at one site share the same prefix. One `for_each` or `count` in the Proxmox provider gives you both the VM and the correct name; no manual numbering.

So "add a new mini-PC" in code is: add one element to the list (or bump count) for that site, run `tofu apply` → new DHCP reservation, DNS, and (once the Proxmox node exists) new K3s VM with the next sequential name (e.g. echo-olympus-2, hydra-olympus-echo-2). No need to remember "what's the next number."

### What OpenTofu manages

- **Node inventory:** One list/count for mini-PCs; optionally MAC per node for PXE/DHCP.
- **DHCP reservations:** Per-node IP (e.g. 10.0.1.128, 10.0.1.132, …) from the same index; generate dnsmasq/Kea config via `templatefile` or use a provider if available.
- **DNS:** A/AAAA records for `echo-<site>-X.yggdrasil.mia.cx` and `hydra-<site>-echo-X.yggdrasil.mia.cx` (or internal only), using the same loop/count.
- **Proxmox VMs:** **Required** for this design. For each Echo node, create one VM on the **corresponding Proxmox node** (echo-olympus-1, echo-olympus-2, …) from a cloud-init template: hostname `hydra-<site>-echo-X`, correct IP (from [Network](../../architecture/network.md)), VMID from IP. The Proxmox provider needs to target the right host (e.g. by node name `echo-<site>-X`); if the provider only talks to one Proxmox, then the "first" Proxmox (e.g. main workstation host) can create VMs on itself, and **remote** mini-PCs (echo-olympus-2, …) may need Ansible or a separate OpenTofu workspace per Proxmox node that creates that node's single K3s VM.
- **Config drive / NoCloud ISO per VM:** OpenTofu generates `user-data` and `meta-data` for each **K3s VM** (not the metal), so cloud-init inside the VM gets hostname `hydra-<site>-echo-X`, join token, and labels.

**Ansible vs OpenTofu:** OpenTofu is the right fit for declarative VM creation, naming, IPs, and DNS. Use it as the source of truth for "how many Echo nodes" and "what's the next name." Ansible can complement for: (1) procedural steps that don't fit Terraform (e.g. "run this once on echo-olympus-2 after it's installed"), or (2) creating the K3s VM on **remote** Proxmox nodes if the Proxmox provider only manages one host and you don't want multiple workspaces. Prefer OpenTofu for all VM and naming logic when the provider can target multiple Proxmox nodes.

**Decisions to document:** Whether the Proxmox provider can create VMs on multiple nodes (echo-olympus-1, echo-olympus-2, …) or only the primary host; if only primary, whether to use Ansible to create the single VM on each remote echo-&lt;site&gt;-X, or one OpenTofu workspace per mini-PC.

## 4. End-to-End Flow (Target)

1. **Add node in code:** In OpenTofu, add one entry to the Echo list (or bump count). Apply → next **echo-&lt;site&gt;-X** and **hydra-&lt;site&gt;-echo-X** are derived; DHCP reservation, DNS, and (when the Proxmox node exists) the K3s VM are created or updated. No manual "what's the next number."
2. **On-site:** Plug new mini-PC into LAN, set BIOS to PXE first. Power on.
3. **PXE (metal):** DHCP assigns IP (from reservation); PXE installs Proxmox with hostname **echo-&lt;site&gt;-X** (e.g. echo-olympus-1). Mini-PC reboots and runs Proxmox.
4. **VM creation:** OpenTofu (or Ansible) creates the **K3s VM** on that Proxmox node (echo-olympus-1) with hostname **hydra-&lt;site&gt;-echo-X**, cloud-init NoCloud attached. VM boots.
5. **First boot (VM):** Cloud-init sets hostname, SSH, installs and joins K3s, applies node labels. Node appears in `kubectl get nodes` as hydra-olympus-echo-1 (etc.).
6. **Ongoing:** Mini-PC always runs Proxmox (echo-olympus-1); the K3s VM disk-boots normally. Re-PXE only when re-provisioning the Proxmox host.

## 5. Phases (Implementation Order)

| Phase | Focus                      | Notes                                                                                     |
| ----- | -------------------------- | ----------------------------------------------------------------------------------------- |
| **A** | PXE server + netboot       | DHCP + TFTP + iPXE; one generic or single-purpose image that boots.                       |
| **B** | Cloud-init image           | Build minimal image (Debian/Ubuntu) with cloud-init; test with NoCloud locally (e.g. VM). |
| **C** | OpenTofu node + network    | Node list, DHCP reservations, DNS; optional config-drive/NoCloud generation.              |
| **D** | Integrate PXE + cloud-init | Point PXE to image + per-node identity (config drive or HTTP by MAC).                     |
| **E** | K3s join and labels        | Reliable token handling and node labels (critical/media) from cloud-init.                 |

Phase 6 in [Migration](../../operations/migration.md) (Mini-PCs) can reference this roadmap: "Use node onboarding (PXE + cloud-init + OpenTofu) once implemented."

## 6. Related Docs

- [Migration](../../operations/migration.md) — Phase 6 (Mini-PCs) is the consumer of this workflow.
- [Kubernetes (Hydra)](../../infrastructure/kubernetes.md) — Current K3s setup and join process.
- [Workload placement](../../infrastructure/workload-placement.md) — Node affinity and labels for new nodes.
- [Architecture](../../architecture/index.md) — Hardware and future mini-PCs.
- [Naming](../../architecture/naming.md) — Hostname and naming conventions.
- [DNS](../../infrastructure/dns.md) — Split-horizon and internal resolution for `*.yggdrasil.mia.cx`.
