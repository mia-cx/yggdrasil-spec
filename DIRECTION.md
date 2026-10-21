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
