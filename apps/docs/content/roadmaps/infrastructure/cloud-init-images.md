---
title: Cloud-Init Images Roadmap
---

# Cloud-Init Images Roadmap

A **catalog** of cloud-init–ready images (and LXC templates) needed for Proxmox-hosted workloads. Complements [Node onboarding](./node-onboarding.md); focuses on _what_ to build rather than the PXE/IaC flow.

## Goal

- **Today:** New VMs and LXCs use stock Proxmox templates (e.g. debian-12-standard) with manual post-provision steps.
- **Target:** Pre-baked cloud-init images and LXC templates for each role so OpenTofu (or manual clone) provisions hosts with first-boot configuration — hostname, SSH, packages, and role-specific setup applied automatically.

## Image Inventory

| Image / Template           | Role                  | Base          | Config source | Notes                                                                                                                         |
| -------------------------- | --------------------- | ------------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **Proxmox** (netboot)      | Bare-metal mini-PC    | Proxmox VE    | PXE + DHCP    | Hostname `echo-<site>-X`; see [Node onboarding §1](./node-onboarding.md#1-pxe-boot-proxmox-on-the-mini-pc).                   |
| **K3s VM**                 | K3s node (Hydra)      | Debian/Ubuntu | NoCloud       | Hostname `hydra-<site>-echo-X`; join token, labels; see [Node onboarding §2](./node-onboarding.md#2-cloud-init-image-k3s-vm). |
| **Wings VM**               | Pelican game servers  | Debian/Ubuntu | NoCloud       | Hostname, Docker, Wings daemon; VM 10.0.1.6, VMID 1006.                                                                       |
| **Storage LXC**            | MergerFS + NFS        | debian-13     | LXC config    | 10.0.1.2, VMID 1002; FUSE passthrough; bind mounts.                                                                           |
| **Authentik LXC** (legacy) | Identity (standalone) | debian-12     | LXC config    | 10.0.1.3, VMID 1003; Docker Compose; reference only (now in K8s).                                                             |
| **Netbird LXC**            | Overlay network mgmt  | debian-12     | LXC config    | 10.0.1.4, VMID 1004; Netbird daemon.                                                                                          |

## Scope by Image

### 1. Proxmox (PXE netboot)

- **Source:** Proxmox installer or custom image.
- **Output:** Bootable image that writes Proxmox to disk with hostname `echo-<site>-X`.
- **See:** [Node onboarding §1](./node-onboarding.md#1-pxe-boot-proxmox-on-the-mini-pc).

### 2. K3s VM

- **Source:** Debian or Ubuntu minimal + cloud-init.
- **Output:** VM template for `hydra-<site>-echo-X`; NoCloud config drive from OpenTofu.
- **user-data:** Hostname, SSH keys, K3s agent install + join, node labels.
- **See:** [Node onboarding §2](./node-onboarding.md#2-cloud-init-image-k3s-vm).

### 3. Wings VM

- **Source:** Debian or Ubuntu minimal + cloud-init.
- **Output:** VM template for Wings host (10.0.1.6, VMID 1006).
- **user-data:**
  - Hostname (e.g. `wings` or `wings-olympus`)
  - Docker install
  - Wings binary install
  - `wings.json` config (Panel URL, keys)
  - `systemd` service enable
- **See:** [Pelican / Wings](../../services/pelican.md), [Migration §Pelican](../../operations/migration.md#pelican--wings).

### 4. Storage LXC

- **Source:** Proxmox LXC template `debian-13-standard`.
- **Output:** Clone-able LXC template with FUSE config and base layout (not full MergerFS — host bind mounts differ per Proxmox host).
- **Post-clone:** Host adds bind mounts in `/etc/pve/lxc/<vmid>.conf`; inside LXC: fstab, MergerFS, NFS export.
- **See:** [Storage LXC](../../infrastructure/storage.md).

### 5. Netbird LXC

- **Source:** Proxmox LXC template `debian-12-standard`.
- **Output:** LXC template with Netbird repo, package, and default config skeleton.
- **user-data / script:** Hostname, Netbird install, join token (from config drive or env).
- **See:** [Infrastructure index](../../infrastructure/index.md), [Migration §Netbird](../../operations/migration.md#netbird-lxc).

### 6. Authentik LXC (legacy)

- **Source:** Proxmox LXC template `debian-12-standard`.
- **Output:** LXC template for Docker Compose–based Authentik (disaster recovery / K3s bootstrap).
- **Note:** Primary deployment is now K8s; this is reference only.
- **See:** [Authentik legacy](../../infrastructure/authentik.md#legacy-lxc-deployment).

## Common cloud-init configuration

Standard first-boot modules to include across VM templates. Reference: [Kubernetes setup](../../infrastructure/kubernetes.md), [Pelican Wings](../../services/pelican.md).

### Networking

- **Interface:** Proxmox VMs typically use `ens18` (virtio). Use `allow-hotplug ens18` so the interface comes up when it appears (avoids "state DOWN" on first boot).
- **Static config** (`/etc/network/interfaces` or cloud-init `network:`):

  ```yaml
  # cloud-init network config
  version: 2
  ethernets:
    ens18:
      addresses: [10.0.1.6/16]
      gateway4: 10.0.0.1
      nameservers:
        addresses: [10.0.0.1, 1.1.1.1]
  ```

- **resolvconf:** For `ifupdown` + `dns-nameservers`, install `resolvconf` and enable it; otherwise `dns-nameservers` in interfaces may not populate `/etc/resolv.conf`.
- **systemd-networkd:** If the image uses NetworkManager or systemd-networkd instead of ifupdown, configure via `netplan` or `networkctl`; cloud-init can write Netplan YAML.

### Sudo

- **Install:** `apt install -y sudo`
- **Add user:** `usermod -aG sudo <username>`
- Cloud-init `users:` can create the user with `groups: sudo` directly.

### Docker

- **Install:** `curl -fsSL https://get.docker.com | sh` or `apt install -y docker.io`
- **Add user to group:** `usermod -aG docker <username>`
- **Enable:** `systemctl enable --now docker`
- Used by: Wings VM, Authentik LXC (legacy), Netbird LXC.

### unattended-upgrades

- **Install:** `apt install -y unattended-upgrades`
- **Configure:** `/etc/apt/apt.conf.d/50unattended-upgrades` — enable security updates, optionally "Allowed-Origins" for backports.
- **Enable:** `dpkg-reconfigure -plow unattended-upgrades` (non-interactive) or ensure `APT::Periodic::Unattended-Upgrade "1"` in `/etc/apt/apt.conf.d/20auto-upgrades`.

### Other useful modules

- **qemu-guest-agent:** For Proxmox VMs — shutdown, snapshot, IP reporting. `apt install -y qemu-guest-agent && systemctl enable --now qemu-guest-agent`
- **nfs-common:** For K3s nodes that mount NFS PVs. `apt install -y nfs-common`
- **SSH hardening:** `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`. Inject SSH keys via cloud-init `users:`.
- **fail2ban** (optional): `apt install -y fail2ban` for SSH brute-force protection.
- **inotify limits** (K3s nodes): `fs.inotify.max_user_instances`, `fs.inotify.max_user_watches` in `/etc/sysctl.d/99-k3s.conf`.

## Build Strategy

- **VMs (K3s, Wings):** Packer + Debian/Ubuntu cloud image → Proxmox template with cloud-init. NoCloud ISO generated per instance by OpenTofu.
- **Proxmox host:** PXE + automated installer or pre-baked disk image; hostname from DHCP/reservation.
- **LXCs:** Proxmox templates + Ansible or script for first-boot; or Packer-based LXC build if reproducible templating is needed.
- **Shared:** Single base (e.g. Debian 12) for VM templates to reduce maintenance; Debian 13 for Storage LXC to match current [Storage LXC](../../infrastructure/storage.md).

## Phases (Implementation Order)

| Phase | Focus             | Images                                    |
| ----- | ----------------- | ----------------------------------------- |
| **A** | K3s VM template   | K3s (for node onboarding)                 |
| **B** | Wings VM template | Wings                                     |
| **C** | LXC templates     | Storage, Netbird (Authentik optional)     |
| **D** | Proxmox netboot   | Proxmox host (integrates with PXE server) |

## Related Docs

- [Kubernetes (Hydra)](../../infrastructure/kubernetes.md) — Base config (network, sudo, resolvconf, qemu-guest-agent, NFS, SSH).
- [Node onboarding](./node-onboarding.md) — PXE, K3s cloud-init, OpenTofu flow.
- [Migration](../../operations/migration.md) — Phase 6 (Mini-PCs), Pelican/Wings, LXC creation.
- [Storage LXC](../../infrastructure/storage.md) — Storage LXC setup and bind mounts.
- [Pelican (Wings)](../../services/pelican.md) — Wings VM architecture.
- [Architecture](../../architecture/index.md) — Hardware and host inventory.
