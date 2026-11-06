# Textile staging

Textile staging on olympus, mesh-only at `https://staging.textile.cx`. It is separate from the live relay in `argocd/discord-mcp/`, which this app never touches.

| Piece               | What runs                                                                                                                                                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `central.yaml`      | `textile-central`, a Deployment of 2: MCP, OAuth, voice sockets and workflow routes. Holds no bot tokens.                                                                                                                 |
| `bot-host.yaml`     | `textile-bot-host`, a StatefulSet of 2, one per node: stored bot tokens, Gateway shards, voice, and the workerd processes that run scripts and workflows.                                                                 |
| `postgresql.yaml`   | `textile-db`, a two-instance CloudNativePG `Cluster` with synchronous replication (`dataDurability: preferred`) on node-local `longhorn-local` volumes, plus its Barman Cloud `ObjectStore` and weekly `ScheduledBackup`. |
| `rustfs.yaml`       | RustFS, the S3-compatible store the database backs up to, on a two-replica Longhorn volume.                                                                                                                               |
| `web.yaml`          | `textile-web`, a Deployment of 2: the website, the same Worker build production serves on Cloudflare, in self-hosted workerd.                                                                                             |
| `ingressroute.yaml` | The private Traefik route and its certificate.                                                                                                                                                                            |

Both tiers run `ghcr.io/mia-cx/textile/server`, and the website runs `ghcr.io/mia-cx/textile/web`, each pinned by digest. CI publishes both on every push to the `textile` branch, tagged `sha-<commit>`. To deploy a newer build, copy the digest from that run's summary, or `docker buildx imagetools inspect ghcr.io/mia-cx/textile/<image>:sha-<commit>`, into the manifests that run it.

One host serves both. The route sends central's paths to central: `/mcp`, `/voice`, `/register`, `/authorize`, `/token`, `/auth/discord/`, the OAuth discovery documents under `/.well-known/`, `/workflows/`, and `/health/`. Everything else goes to the website, which asks search engines not to index it.

Backups use the [Barman Cloud plugin](../cnpg-barman-cloud/README.md): WAL is archived continuously and a base backup runs weekly, Sundays at 03:00 UTC, kept 14 days, in bucket `textile-backups`. RustFS lives on the same cluster, so backups are not off-site yet.

## Before the first sync

1. Run `scripts/bootstrap-textile.sh` from a machine whose kubectl reaches olympus. It walks through the Discord redirect URI and client secret, the allowlist, and generates the other keys, creating these Secrets in `textile`:

   | Secret              | Keys                                                            | Read by                                                                                            |
   | ------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
   | `textile-oauth`     | `DISCORD_OAUTH_CLIENT_SECRET`, `DISCORD_OAUTH_ALLOWED_USER_IDS` | central and the website; bot hosts read the allowlist                                              |
   | `textile-crypto`    | `OAUTH_ENCRYPTION_KEY`                                          | central                                                                                            |
   | `textile-bot-hosts` | `BOT_HOST_SECRET`                                               | both tiers                                                                                         |
   | `textile-vault`     | `TOKEN_VAULT_KEY`                                               | bot hosts. Its copies in iCloud Keychain and offline are the only way to read a restored database. |
   | `textile-rustfs`    | `RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY`                        | RustFS and the database's backups                                                                  |
   | `textile-web`       | `SESSION_KEY`                                                   | the website, which seals its sign-in cookies with it                                               |

   CloudNativePG creates `textile-db-app`, whose `uri` the bot hosts use.

2. In the Discord Developer Portal, the Textile application (`1162037890742759424`) needs the redirects `https://staging.textile.cx/auth/discord/callback` for central and `https://staging.textile.cx/auth/callback` for the website. The wizard opens the page.
3. Give the mesh a way in, as for every row in [the private Traefik's table](../traefik-internal/README.md#per-service-shape): add yourself to `svc-textile` in Authentik (`role-admin` includes it) and sign in to NetBird again so the group arrives. Then create NetBird policy `textile` (source `svc-textile`, destination `res-textile`, unidirectional TCP 443) and DNS zone `staging.textile.cx` (distribution group `svc-textile`, search domain off) with an apex A record to `10.43.0.155`.
4. cert-manager issues the certificate by DNS-01 through Cloudflare, so `textile.cx` must be a zone that the `cloudflare-api-token` Secret in `cert-manager` can edit.

Merging deploys: ArgoCD creates the plugin (`cnpg-barman-cloud`), the `longhorn-local` StorageClass (`k3s-base`), the private route (`traefik-internal`), and this app.

## Verify

```sh
kubectl -n textile get cluster textile-db            # 2 instances, "Cluster in healthy state"
kubectl -n textile get pods -o wide                  # bot hosts and database instances on different nodes
kubectl -n textile get backup                        # the immediate backup reaches "completed"
kubectl -n textile get cluster textile-db \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}'   # True
kubectl -n textile logs statefulset/textile-bot-host | head   # "discord-mcp bot-host listening"
curl -sf https://staging.textile.cx/health/ready     # from a mesh device in svc-textile
curl -sI https://staging.textile.cx/ | grep -i x-robots-tag   # the website: "noindex"
```

Then sign in with `node scripts/login.mjs https://staging.textile.cx/mcp` from the Textile repo, call any tool with a test bot's token, and watch the bot come online in Discord. It goes offline 24 hours after the last call.

## Point-in-time restore into a scratch cluster

This proves the backups restore, without touching `textile-db`. The scratch cluster reads the same `ObjectStore` but archives nowhere.

1. Note a time to restore to, after the latest completed base backup and before now, in RFC 3339 (`date -u +%Y-%m-%dT%H:%M:%SZ`). Write something you can look for before that time and something else after it.
2. Create the scratch cluster:

   ```sh
   kubectl apply -f - <<'EOF'
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata:
     name: textile-db-restore
     namespace: textile
   spec:
     imageName: ghcr.io/cloudnative-pg/postgresql:18.6-standard-trixie
     instances: 1
     storage:
       size: 10Gi
       storageClass: longhorn
     bootstrap:
       recovery:
         source: textile-db
         recoveryTarget:
           targetTime: "2026-11-05T12:00:00Z"   # the time from step 1
     externalClusters:
       - name: textile-db
         plugin:
           name: barman-cloud.cloudnative-pg.io
           parameters:
             barmanObjectName: textile-backups
             serverName: textile-db
   EOF
   kubectl -n textile get cluster textile-db-restore -w   # until "Cluster in healthy state"
   ```

3. Check the data: what you wrote before the target time is there, and what you wrote after it is not.

   ```sh
   kubectl -n textile exec -it textile-db-restore-1 -- psql textile -c '\dt'
   ```

4. Delete the scratch cluster and its volume: `kubectl -n textile delete cluster textile-db-restore`. ArgoCD ignores it, since it is not in this directory, so leaving it behind costs only disk.
