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

The CPA and customised Keeper workloads are running with persistent Longhorn
volumes. PR #61 adds GitOps ownership, private routes and the dedicated
`svc-cliproxyapi` permission; activation awaits merge and a permission-holding
NetBird sign-in.
