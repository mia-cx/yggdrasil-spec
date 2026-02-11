# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Repository overview

Infrastructure-as-code for a personal homelab. The `terraform/` folder uses OpenTofu (Terraform-compatible) to manage providers like Cloudflare and Proxmox; the `docker/` folder contains a minimal containerized toolchain for running OpenTofu reproducibly.

Key entry points:

- `terraform/main.tf` references two local modules (`./modules/cloudflare`, `./modules/proxmox`) and includes an example `cloudflare_record` resource. If `terraform/modules/*` are missing, they are expected to be added later.
- `docker/Dockerfile` produces a lightweight Alpine image with the `tofu` binary and basic utilities; `docker/docker-compose.yaml` builds/tag this as `miacx/tofu:dev`.

State: no backend is declared, so OpenTofu will default to local state in `terraform/` unless a backend is added.

## Common commands

You can work either with a locally installed OpenTofu or entirely via the provided Docker image.

- Initialize providers (first run or after provider/module changes):
  - Local: `tofu init -chdir=terraform`
  - Container: `docker run --rm -it -v "$PWD":/workspace -w /workspace miacx/tofu:dev tofu init -chdir=terraform`

- Format and validate configuration:
  - Local: `tofu fmt -recursive -chdir=terraform && tofu validate -chdir=terraform`
  - Container: `docker run --rm -v "$PWD":/workspace -w /workspace miacx/tofu:dev sh -lc 'tofu fmt -recursive -chdir=terraform && tofu validate -chdir=terraform'`

- Create an execution plan:
  - Local: `tofu plan -chdir=terraform`
  - Container: `docker run --rm -it -v "$PWD":/workspace -w /workspace miacx/tofu:dev tofu plan -chdir=terraform`

- Apply changes (interactive approval):
  - Local: `tofu apply -chdir=terraform`
  - Container: `docker run --rm -it -v "$PWD":/workspace -w /workspace miacx/tofu:dev tofu apply -chdir=terraform`

- Target a single resource (useful for focused changes while developing):
  - Example: `tofu plan -chdir=terraform -target=cloudflare_record.tofu-example`

- Upgrade provider locks (when needed):
  - `tofu init -upgrade -chdir=terraform`

Notes:

- Provider credentials (e.g., Cloudflare) must be exported in the environment as required by the provider; when using the container, pass them through with `-e VAR=...` or via your shell environment.
- If you prefer Compose, you can build the image with `docker compose -f docker/docker-compose.yaml build` and then run equivalent commands using `docker run` against the `miacx/tofu:dev` image.

## Architecture (big picture)

High-level intent for the homelab and network, derived from the design plan under `.cursor/plans/homelab_k3s_migration_e333488d.plan.md` and `terraform/`:

- Proxmox-based virtualization hosts the stack. A lightweight Storage LXC exposes two NFS exports:
  - NVMe-backed "critical" data
  - HDD-backed media via MergerFS
- Kubernetes via K3s with kube-vip for high availability and fixed virtual IPs (control plane and ingress). Longhorn is used for small, block-level persistence; bulk data uses NFS PVs.
- Identity and access through Authentik (OIDC), used by internal services and Netbird.
- Netbird provides the overlay network plus split-horizon DNS for internal-only resolution of `*.yggdrasil.mia.cx`.
- Traefik (bundled with K3s) handles ingress; authenticated routes use Authentik forward-auth.
- Externally, Cloudflare DNS and Workers present friendly landing pages for non-overlay clients; internal names resolve to overlay or LAN IPs.
- OpenTofu manages external DNS records and (eventually) Proxmox resources via local modules (`./modules/cloudflare`, `./modules/proxmox`).

This repository currently includes the OpenTofu scaffold and example Cloudflare record; cluster/application manifests and Proxmox module contents are expected to live under `terraform/modules/` as they are developed.

## Conventions specific to this repo

- Prefer `-chdir=terraform` with OpenTofu so commands can be run from repo root.
- Keep provider credentials out of VCS; rely on environment variables expected by each provider.
- When iterating on a single change, use `-target` with care to avoid partial, drift-prone plans; remove it for full applies.

## Related docs to consult in-repo

- `.cursor/plans/homelab_k3s_migration_e333488d.plan.md` — authoritative, detailed migration/design plan for networking, storage, K3s, Authentik, Netbird, Traefik, and DNS.
- `README.md` — brief repository description.