# Yggdrasil

Manage Mia's homelab infrastructure, K3s services and operational documentation
through this repository. ArgoCD reconciles cluster applications from `main`.

## Access direction

Private services use isolated NetBird ingress with per-service network
destinations and Hecate permissions. Existing service cutovers remain separate
decisions Mia approves. The accepted contracts and migration gates are linked
from `AGENTS.md` and the infrastructure documentation.

## AI proxy

CLIProxyAPI provides a private endpoint for Mia's Claude Code, Codex, Devin and
Cursor accounts. CPA Usage Keeper preserves usage history and exposes six
overview metrics with angular sparklines and a daily-average strip. Account
sign-ins remain under Mia's control.

Codex banked reset tickets are for confirmed weekly quota exhaustion. The
proxy's error path checks the account's current weekly limit before redeeming
one and retrying. Five-hour limits and capacity errors preserve tickets.

NetBird carries incoming connections only. Provider traffic exits through the
normal cluster WAN gateway, with explicit egress policies excluding unrelated
private destinations. Credentials and OAuth state stay outside Git.

PR #61 is merged. ArgoCD owns the healthy CPA and customised Keeper workloads,
persistent Longhorn volumes, private routes and dedicated `svc-cliproxyapi`
permission. Its JWT-issued NetBird group grants TCP 443 to both destinations;
private DNS maps `cpa.mia.cx` and `cpa-usage.mia.cx` to their dedicated Services.
Claude and Codex provider sign-ins work. Hephaestus has a dedicated primary
NetBird machine identity scoped to CPA, independent of its Repair client.
Its `claude-cpa` and `codex-cpa` launchers pass real provider requests while
preserving the ordinary client commands and host DNS/gateway.

## Storage direction

The NVMe share (`10.0.1.2:/mnt/nvme`) holds hot data: Nextcloud, VM disks and
download staging. Datasets, corpora and run outputs live on the HDD share under
`/mnt/media/private`.

Mia's Nextcloud is a discoverable archive, built in three steps:

1. Done (2026-11-25): byte-identical duplicates were merged and files were moved
   into the new layout, freeing 105.6 GiB. Personal areas are type-first:
   `Photos/YYYY/YYYY-MM/`, `Documents/`, and `Videos/` for screen recordings.
   `Projects/<name>/` holds Patch, Prism Plaza and client work, organised by
   name. Releases are named `Releases/<release date> <title>/`, and each DAW
   session keeps its old versions in its own `versions/` folder. `Library/`
   holds sample packs, presets and plugin data; `Software/Config/` holds app
   settings. Installers, DAW factory packs and build output were deleted as
   re-findable, except the irreplaceable ASIO Link Pro patcher. Copies inside
   DAW projects stay, so sessions keep opening. The move ran on disk followed by
   `occ files:scan`, so Mia reshares any links she still needs.
2. Add HDD-backed Nextcloud External Storage for archive material.
3. Mark files untouched for 90 days as archive candidates, without moving
   them, so the first rounds show what qualifies before any migration.
   Moving into External Storage changes file IDs and drops shares on the moved
   items.

Photos stay in Nextcloud for now; Immich becomes their home later.
