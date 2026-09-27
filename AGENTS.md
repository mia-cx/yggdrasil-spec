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

## Planning sources

- For NetBird architecture or migration work, read the [Wayfinder map](https://github.com/mia-cx/yggdrasil-spec/issues/5). Its accepted resolutions take precedence over older scaffold and roadmap descriptions.
- For multi-site, VM HA, or cross-cluster service/storage design, read [Multi-site resilience](apps/docs/content/roadmaps/infrastructure/multi-site-resilience.md). It separates available options from accepted decisions.
- For documentation-only verification, format-check new Markdown with `pnpm exec prettier --check <file>`, then build Quartz with `cd apps/docs && node --no-deprecation quartz/bootstrap-cli.mjs build --output <absolute-temporary-directory>`. The root build script does not invoke a Quartz build.
- For DNS or ingress changes, read [DNS](apps/docs/content/infrastructure/dns.md) and the [accepted resolution](https://github.com/mia-cx/yggdrasil-spec/issues/10#issuecomment-5742199940). Kubernetes CoreDNS at `10.43.0.10` is separate from the legacy `10.0.128.3` exposure; migration gates apply before retiring either legacy DNS Service.
- Prove NetBird stability with a canary/client pilot and obtain Mia's sign-off before restricting any existing production service to the mesh. During setup, preserve current Traefik, routes, public DNS, and existing access. Each later service cutover separately needs ready users, working Hecate/native authentication, and Mia's approval. Rollback after cutover must not silently reopen the private origin.
- For public callback exceptions, read the [endpoint review](https://github.com/mia-cx/yggdrasil-spec/issues/10#issuecomment-5719788672). Browser OAuth redirects differ from server-delivered webhooks; existing public ingress labels do not justify exceptions. Runtime integration inventory remains a cutover gate.
- ArgoCD initially uses [polling without a public webhook](https://github.com/mia-cx/yggdrasil-spec/issues/10#issuecomment-5742074779). Revisit an authenticated, narrowly scoped webhook only if repository-change detection delays become annoying.
- For K3s mesh work, read the [accepted integration resolution](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743564646). It selects the four-pod routing pool, explicit workload egress, and DNS contract. Its OS-level node clients are superseded: K3s nodes run no NetBird client, because k3s's bundled iptables/kube-router crash on NetBird's nftables rules ([kube-router#1788](https://github.com/cloudnativelabs/kube-router/issues/1788), [k3s#11493](https://github.com/k3s-io/k3s/issues/11493)). Routine node SSH goes through the `olympus-lan` router. The independent recovery path is the unprivileged Repair netstack client from the accepted dual-mesh design, which writes no kernel firewall rules, scoped under [#24](https://github.com/mia-cx/yggdrasil-spec/issues/24). Keep Repair and replaceable routing identities distinct; enforce pod egress policy rather than treating mesh membership as workload authorization.
- For selected dual-mesh hosts, use the [accepted coexistence design](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743020199): normal primary client plus an independent unprivileged Repair netstack service. Preserve host DNS and isolate client state, sockets, and UDP ports. Joint runtime tests remain a cutover gate. Netstack mode is distinct from ordinary userspace WireGuard with a host TUN interface.
- For Wings/Hermes connections, read the [routing contract](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743163099). Wings needs authorized browser WebSockets and signed file transfers, not only machine calls. Keep backend mesh targets distinct from frontend aliases to avoid routing loops. Wings SFTP uses a separate NetBird-only alias via Pelican's daemon_sftp_alias; reject public and direct LAN access at its approved cutover.
- For private-ingress pilots, follow the [canary isolation contract](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743501773): distinct CRD ingress class and route-local certificate Secrets. Avoid introducing another default TLSStore, TLSOption, or IngressClass that could affect current Traefik.
- For enrollment, session, or revocation work, read [Choose enrollment and permission lifecycle](https://github.com/mia-cx/yggdrasil-spec/issues/13), including its accepted boundaries. Personal devices use self-service confirmation and 30-day NetBird SSO renewal; app sign-in uses Hecate, and shared TVs use restricted appliance identities. Service-permission removal cuts NetBird access to that private service within 24 hours of the Hecate change: running sessions may finish, new requests must fail, and unrelated grants stay intact. TVs enroll through single-use setup keys with no auto-groups and a 24-hour expiry; the lifecycle ticket is [resolved](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5848385171). Verify consent and revocation in the chosen clients and Community Edition integration before cutover.
- For Jellyfin revocation, follow the [network cutoff contract](apps/docs/content/infrastructure/netbird.md#jellyfin-network-cutoff), generalized to [per-service destinations](apps/docs/content/infrastructure/netbird.md#per-service-network-destinations): every private service gets its own Traefik entrypoint port, ClusterIP Service, and NetBird resource for enforcement. Revoke service access through NetBird; credentials can remain intact. Prove new requests fail within 24 hours and other grants remain usable; mid-stream cutoff is not required. [TV permissions](apps/docs/content/infrastructure/netbird.md#shared-appliance-permissions) are capped by both the owner's current grants and the TV allowlist; owner revocation cascades to owned TVs. Public Immich, Nextcloud, and Vaultwarden stay outside the NetBird plan; their sign-in, sessions, and revocation are Hecate matters.
- For permission propagation, plan the hourly Hecate-to-NetBird sync job. Community Edition syncs JWT groups only at sign-in and paid IdP Sync is out of scope, so a scheduled K3s job reads effective permissions from Hecate and sets each person's NetBird groups through the Management API. Per the [sync design](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5848276326), JWT sync stays on for grants at sign-in while the job covers removals and TVs; it never creates access groups (JWT-issued only, each bootstrapped by a permission-holding sign-in). TVs are Hecate service accounts storing owner and peer ID; sync failures email on start and recovery. The bound and job [cover NetBird access only](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5848330338); public apps stay a Hecate matter. TV owners and allowlists live in Hecate; this repository never holds personal data. Verify committed effective permissions before applying changes; [Hecate membership notifications](https://github.com/mia-cx/yggdrasil-spec/issues/13#issuecomment-5814998437) can precede the change.
- For NetBird migration execution, follow the [migration plan](apps/docs/content/roadmaps/infrastructure/netbird-migration.md): foundation, Hecate, K3s, sync job, a 14-day pilot with sign-off, then grouped per-service cutovers Mia approves one decision at a time. Sign-off makes services eligible, not migrated. After cutover, fix forward; reopening a public route is a per-service revert Mia approves.

## AdGuard filtering boundary

- Scope (live): human mesh devices (`netbird-enroll`) get AdGuard filtering; services and infrastructure use unfiltered DNS.
- Outage policy (live): human devices fall back to unfiltered DNS when AdGuard is unavailable, through `1.1.1.1` as the second nameserver in the same `adguard` nameserver group. Re-verify failover after changing that group.
- Placement (live): AdGuard Home runs in Docker on the primary NetBird VM, outside K3s, in the network namespace of the `olympus-dns` NetBird sidecar; no host DNS port is published.
- Distribute the AdGuard primary nameserver to human-device groups, not `All`. Keep service peers outside those groups, including administrator-owned servers.
- Private records remain in NetBird Custom Zones. Distinguish Management-side DNS disablement from the client --disable-dns flag: inspected client v0.78.1 preserves its local DNS service while leaving OS resolver settings untouched. Read the [service DNS evidence](https://github.com/mia-cx/yggdrasil-spec/issues/12#issuecomment-5743310500) before configuring application lookups.
- DNS assignment is per peer, not per process. Services sharing a human device need an explicit unfiltered resolver path.
