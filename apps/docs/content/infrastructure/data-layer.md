---
title: Data Layer
---

# Data Layer

## Overview

| Property  | Value                 |
| --------- | --------------------- |
| Type      | K8s                   |
| Namespace | Various (per service) |
| Storage   | Longhorn              |

Database and caching architecture for K3s services. Follows three patterns: shared PostgreSQL, per-service Redis, and isolated Vaultwarden SQLite.

| Principle               | Implementation                                  |
| ----------------------- | ----------------------------------------------- |
| Shared PostgreSQL       | Single instance, separate databases per service |
| Isolated Redis          | One Redis instance per service                  |
| Vaultwarden independent | SQLite on separate Longhorn volume              |

## Setup

```bash
kubectl apply -f argocd/databases/storage.yaml
```

## Configuration

### PostgreSQL (Shared)

Single PostgreSQL instance on Longhorn, with per-service databases and users.

```
PostgreSQL (Longhorn volume, 2 replicas)
├── database: nextcloud    → user: nextcloud
├── database: forgejo      → user: forgejo
└── database: [future]     → user: [service]
```

**Why shared?**

- Lower memory footprint (one PG process vs many)
- Single backup job (`pg_dumpall`)
- Unified failover: node dies → Longhorn recovers → pod reschedules
- Sufficient for homelab workloads

**Isolation:** Each service gets a dedicated database and user with `GRANT ALL` only on its database. Compromise of one service's credentials doesn't expose others.

### Redis (Per-Service)

Separate Redis instance for each service that needs caching/sessions.

```
redis-nextcloud  (Longhorn or emptyDir)
redis-forgejo    (Longhorn or emptyDir)
redis-[service]  (...)
```

**Why separate?**

- No resource contention between services
- Failure isolation (Redis crash only affects one service)
- Independent tuning (different maxmemory policies)
- Clear ownership for debugging

**Persistence options:**

| Mode     | Use Case                        |
| -------- | ------------------------------- |
| emptyDir | Pure cache, loss is acceptable  |
| Longhorn | Session persistence, job queues |

For most services, `emptyDir` is sufficient -- cache rebuilds on restart.

### Vaultwarden (Isolated)

Vaultwarden runs completely separate from the shared data layer on a dedicated Longhorn volume with SQLite.

**Why isolated?**

- Root of trust: password manager shouldn't depend on shared infrastructure
- No circular dependencies: Authentik creds stored in Vaultwarden, not vice versa
- Independent failover: Vaultwarden survives PostgreSQL issues
- Simpler: SQLite is sufficient for personal/family use

**Auth model:** Hybrid -- SSO via Authentik and master password login both supported. Master password + hardware 2FA (YubiKey) as fallback if Authentik is unavailable. Vault encryption is tied to master password (not SSO).

## Storage Summary

| Component          | Storage Type         | Replicas | Backup Strategy              |
| ------------------ | -------------------- | -------- | ---------------------------- |
| PostgreSQL         | Longhorn             | 2        | pg_dumpall + volume snapshot |
| Redis instances    | emptyDir or Longhorn | 1-2      | Usually not needed           |
| Vaultwarden SQLite | Longhorn             | 2        | Volume snapshot + file copy  |

## Failover Behavior

| Scenario        | PostgreSQL                                     | Redis                       | Vaultwarden                          |
| --------------- | ---------------------------------------------- | --------------------------- | ------------------------------------ |
| Pod crash       | Auto-restart                                   | Auto-restart                | Auto-restart                         |
| Node failure    | Longhorn reattaches, pod reschedules (~30-60s) | Pod reschedules, cache cold | Longhorn reattaches, pod reschedules |
| Data corruption | Restore from pg_dump                           | N/A (ephemeral)             | Restore from backup                  |

> This is not zero-downtime HA. Services experience brief outage during failover. For a homelab, this trade-off (simplicity over complexity) is acceptable.
