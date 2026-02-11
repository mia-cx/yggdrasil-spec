---
title: Workload Placement (Node Affinity)
---

# Workload Placement (Node Affinity)

Use **node labels** plus **node affinity** so only certain workloads run (and fail over) to certain nodes. There is no separate “failover allowlist” in Kubernetes—scheduling rules define where pods can run.

## Convention

We use the label key prefix **`workloads/<type>`** so one node can accept multiple workload types (Kubernetes allows only one value per label key, so we use one key per type).

### Management / architecture (no node affinity)

Low-level cluster components run **unconstrained** so the scheduler can place them anywhere. Intentionally no `workloads/*` label requirement — experimental nodes should only get lightweight workloads; management stays flexible.

| Component   | Affinity | Notes |
| ----------- | -------- | ----- |
| Longhorn    | none     | Storage; place via topology or leave to scheduler |
| Traefik     | none     | Ingress; K3s HelmChartConfig has no affinity |
| CoreDNS     | none     | Cluster DNS |
| cert-manager controller | **critical** (when deployed) | Not in this repo; where you install it, add `workloads/critical` affinity so it doesn’t land on experimental nodes |
| cloudflare-ddns | **critical** | Constrained so DNS updates don’t run on experimental hardware |

**Replication:** Kubernetes does **not** auto-scale replica count by node count. Set `replicas` explicitly (e.g. 2 for HA) or use a **DaemonSet** (one pod per node). Use **topology spread constraints** to spread pods across zones/nodes; replicas are still fixed (e.g. `maxSkew: 1`, `whenUnsatisfiable: ScheduleAnyway` to prefer spreading). Keep replicas ≤ number of nodes that can run the workload.

### Workload labels (constrained)

| Label                   | Nodes        | Workloads |
| ----------------------- | ------------ | --------- |
| `workloads/critical`    | antheia, athena | Authentik, Vaultwarden, cert-manager (controller), cloudflare-ddns |
| `workloads/media`       | athena only  | Jellyfin, Tunarr, Tdarr; also required for *arr + downloaders |
| `workloads/downloading` | athena only  | SABnzbd, Sonarr, Radarr, Prowlarr, etc. |
| `workloads/cloud-data`  | athena only  | Immich, Nextcloud (photo/library and file sync) |

- **antheia** (old server): label `workloads/critical` only → runs critical services; when athena is down, those services still run on antheia.
- **athena**: label `workloads/critical`, `workloads/media`, `workloads/downloading`, and `workloads/cloud-data` → runs critical + media + cloud-data stacks.

## Label the nodes

Run once per node (from any machine with kubeconfig):

```bash
# antheia: critical only
kubectl label node antheia workloads/critical=

# athena: critical + media + downloading + cloud-data (multiple labels, same prefix)
kubectl label node athena workloads/critical=
kubectl label node athena workloads/media=
kubectl label node athena workloads/downloading=
kubectl label node athena workloads/cloud-data=
```

To remove a label: `kubectl label node <name> workloads/critical-` (trailing hyphen), then re-apply as needed.

## Critical replication and site awareness

### Replicas for critical workloads

There is **no built-in way** to set replicas to “number of nodes with this label”. You set `replicas` explicitly (or use a custom controller/script that watches nodes and updates a Deployment).

- **Stateless critical** (e.g. a proxy or API that can scale horizontally): set `replicas` to the number of critical nodes for maximum resilience, but **capping at 5** is usually enough — beyond that you get diminishing returns and extra load. Update replicas when you add/remove critical nodes.
- **Stateful critical** (Authentik, Vaultwarden with RWO storage): typically **1 or 2** replicas; more usually need shared storage or app-specific clustering. Don’t scale past what the app and storage support.

Use **topology spread** (see below) so replicas are spread across sites/nodes instead of stacking on one.

### Sites: making the scheduler site-aware

Label nodes with a **site** identifier so the scheduler can spread or pin workloads per site:

```bash
# Example: one label key for all sites, value = site name
kubectl label node athena topology.kubernetes.io/site=athena
kubectl label node antheia topology.kubernetes.io/site=antheia
```

Use a single key (e.g. `topology.kubernetes.io/site` or `site`) consistently so **pod topology spread** can use it.

**Spread across sites (no minimum per site):** add a topology spread constraint so pods are distributed across sites (reduces skew):

```yaml
spec:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/site   # or your site label key
      whenUnsatisfiable: ScheduleAnyway         # prefer spread; DoNotSchedule = hard requirement
      labelSelector:
        matchLabels:
          app: my-critical-app
```

**At least x replicas per site (e.g. Netbird):** topology spread does **not** guarantee “at least 2 per site”. To get a minimum per site:

- **Option A — One Deployment per site:** create a Deployment per site with `nodeSelector: topology.kubernetes.io/site=athena` and `replicas: x`. Guarantees x pods in that site; use a second Deployment for the other site.
- **Option B — DaemonSet per site:** one DaemonSet per site with `nodeSelector: topology.kubernetes.io/site=athena`. You get one pod per node in that site (minimum per site = number of nodes in that site).

For **Netbird exit-nodes** “at least x per site”: use Option A (Deployment per site with `replicas: x` and `nodeSelector`) or Option B (DaemonSet per site) so each site has the desired count.

### Sites vs zones

In this setup, **one site = one zone**. Use `topology.kubernetes.io/zone=<site-name>` (e.g. `olympus`, `elysium`, `arcadia`) so Longhorn and the scheduler treat each location as a failure domain and spread replicas across sites when possible.

**Multiple zones per site** is a datacenter-style pattern: e.g. one zone per rack or per “UPS group” (one or two redundant UPSes per rack) so a single rack or power boundary is one zone. We don’t expect multiple racks per site here, but it’s useful to know if you later have several failure domains in one building (different circuits, racks, or UPS groups).

## Set affinity on workloads

Within one `nodeSelectorTerm`, all `matchExpressions` are **AND**ed: the node must satisfy every expression. Multiple `nodeSelectorTerms` are **OR**ed: the node must match at least one term.

### Critical (HA) services

Authentik, Vaultwarden, cert-manager (controller), cloudflare-ddns: allow scheduling only on nodes that have `workloads/critical` (antheia and athena), so they don’t fail over to experimental or weak hardware.

In the Helm values or Deployment:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: workloads/critical
              operator: Exists
```

### Media only (e.g. Jellyfin)

Jellyfin (and any app that only needs the media library): require `workloads/media` only.

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: workloads/media
              operator: Exists
```

### Media + downloading (SABnzbd, Sonarr, Radarr, Prowlarr, etc.)

Apps that need both the media role and access to download/staging storage: require **both** labels in the same term (AND).

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: workloads/media
              operator: Exists
            - key: workloads/downloading
              operator: Exists
```

### Cloud-data (Immich, Nextcloud)

Immich and Nextcloud: require `workloads/cloud-data` (nodes that host photo library / file sync data).

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: workloads/cloud-data
              operator: Exists
```

### Netbird (unconstrained)

Netbird management runs on an LXC (external); the exit-node is a **DaemonSet** with no node affinity, so one pod runs on every node that tolerates it. To get **at least x exit-nodes per site**: label nodes with a site identifier (e.g. `topology.kubernetes.io/zone=site-a` or custom `site=athena`). The DaemonSet already gives one per node; for a minimum count per site you’d need either multiple DaemonSets (one per site, with `nodeSelector`) or a Deployment per site with `nodeSelector` and `replicas: x` plus topology spread so they don’t all land on one node.

### Co-locating backend with cache or database (paired scheduling)

To minimize latency between backend and a companion (cache or DB read replica), **co-locate them on the same node** using **pod affinity** in both directions. Traffic between backend and cache/DB is usually much heavier than client→frontend or client→backend, so keeping each backend pod on the same node as its cache (or a DB read replica) reduces latency and load.

**Mechanics:**

1. Set **the same replica count** for both workloads (e.g. backend and Redis both `replicas: 3`). Kubernetes does not auto-scale one from the other; keep them in sync in Helm/values or GitOps.
2. Add **pod affinity** on both so each pod is scheduled only on a node that already has a pod of the other:
   - Backend: require `podAffinity` for the cache (or DB replica) with `topologyKey: kubernetes.io/hostname`.
   - Cache (or DB replica): require `podAffinity` for the backend with `topologyKey: kubernetes.io/hostname`.
3. Keep your existing **node affinity** (e.g. `workloads/critical`, site) on both so they still only run on allowed nodes.

**Backend (example):**

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: workloads/critical
              operator: Exists
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: myapp-redis
        topologyKey: kubernetes.io/hostname
```

**Redis / cache (example):**

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: workloads/critical
              operator: Exists
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: myapp-backend
        topologyKey: kubernetes.io/hostname
```

Result: with replicas 3 and 3, the scheduler places three pairs (one backend + one cache per node) across up to three nodes. Replicas still spread across any node that matches node affinity; pairing is per node.

---

## Backend–database vs backend–cache (architecture)

**Prefer pairing backend with Redis (or another cache), not with multiple “primary” databases.**

- **Backend + Redis (paired):** Both can be stateless (or Redis is a local cache). No shared state to sync; no write conflicts. One canonical **primary database** (single instance or primary + sync replica for HA) handles all writes; backends read/write the primary and use **local Redis** for caching and session. Paired scheduling gives each backend a Redis on the same node → low latency for cache hits.
- **Backend + multiple primary DBs (avoid):** Running one Postgres “primary” per node and trying to keep them in sync is complex: replication lag, split-brain, and write conflicts. Not recommended.

**Postgres: one canonical primary + read replicas that sync.**

Postgres supports a **primary (read–write) + read replicas (read-only)** model. Replicas continuously sync from the primary via **streaming replication** (built-in) or logical replication. There is one source of truth; replicas are eventually consistent for reads.

- **Primary:** Single instance (or two with sync replication for HA). All writes go here.
- **Read replicas:** One or more; sync from primary. Backends can read from a **local** replica (pair backend with replica via pod affinity) to minimize read latency; writes still go to the primary.

So: **one canonical primary DB**, optionally **read replicas** that sync from it. Use **paired scheduling for backend ↔ Redis** (cache/session on same node). Optionally use **paired scheduling for backend ↔ Postgres read replica** on the same node for read-heavy workloads; keep a single primary for writes.

| Approach | Use case |
| -------- | -------- |
| One primary DB + backend ↔ Redis paired | Writes to primary; cache/session in Redis, co-located with backend |
| One primary + read replicas + backend ↔ replica paired | Read-heavy; backend reads from local replica, writes to primary |

## Summary

| Goal | How |
| ---- | --- |
| Allowlist of nodes for a workload | Node affinity with a label only those nodes have |
| Require two (or more) labels (AND) | Put multiple `matchExpressions` in the same `nodeSelectorTerm` |
| Critical HA across antheia + athena | `workloads/critical` on both; critical apps use affinity for `workloads/critical` (Exists) |
| Media only (e.g. Jellyfin) | `workloads/media` on nodes; affinity with one matchExpression for `workloads/media` |
| Media + downloading (*arr, SABnzbd) | `workloads/media` and `workloads/downloading` on nodes; affinity with both in one term |
| Multiple workload types on one node | Use multiple keys: `workloads/critical`, `workloads/media`, `workloads/downloading`, `workloads/cloud-data` (one value per key) |
| Management (Traefik, Longhorn, CoreDNS) | No affinity; scheduler decides |
| Replicas vs node count | Set `replicas` explicitly or use DaemonSet; K8s does not auto-scale replicas by node count |
| Netbird exit-nodes | DaemonSet = one per node; for min per site use node labels + multiple DaemonSets or Deployments per site |
| Critical replicas | Set manually; stateless often cap at 5; stateful (Authentik, Vaultwarden) usually 1–2 |
| Site-aware scheduling | Label nodes with `topology.kubernetes.io/site=<name>`; use topology spread to spread across sites; for “min x per site” use one Deployment or DaemonSet per site with nodeSelector |
| Co-locate backend + cache/replica (same node) | Same replica count for both; pod affinity both ways with `topologyKey: kubernetes.io/hostname`; keep node affinity so both only run on allowed nodes |
| Backend–DB architecture | One canonical primary DB; pair backend with Redis (cache) on same node; optionally pair backend with Postgres read replica for read latency; avoid multiple primary DBs |

Adding a new node: add the `workloads/<type>` and (if used) `topology.kubernetes.io/site` labels; update replicas for critical workloads if you want one per critical node (capped at 5 for stateless).
