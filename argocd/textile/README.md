# Textile

Textile's closed alpha on olympus at `https://textile.cx`. The website and its sign-in are public; MCP, voice and workflows are mesh-only. It is separate from the live relay in `argocd/discord-mcp/`, which this app never touches.

| Piece               | What runs                                                                                                                                                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `central.yaml`      | `textile-central`, a Deployment of 2: MCP, OAuth, voice sockets and workflow routes. Holds no bot tokens.                                                                                                                 |
| `bot-host.yaml`     | `textile-bot-host`, a StatefulSet of 2, one per node: stored bot tokens, Gateway shards, voice, and the workerd processes that run scripts and workflows.                                                                 |
| `postgresql.yaml`   | `textile-db`, a two-instance CloudNativePG `Cluster` with synchronous replication (`dataDurability: preferred`) on node-local `longhorn-local` volumes, plus its Barman Cloud `ObjectStore` and weekly `ScheduledBackup`. |
| `rustfs.yaml`       | RustFS, the S3-compatible store the database backs up to, on a two-replica Longhorn volume.                                                                                                                               |
| `web.yaml`          | `textile-web`, a Deployment of 2: the website, the same Worker build production serves on Cloudflare, in self-hosted workerd.                                                                                             |
| `ingressroute.yaml` | The public and private Traefik routes and their shared certificate.                                                                                                                                                       |

Both tiers run `ghcr.io/mia-cx/textile/server`, and the website runs `ghcr.io/mia-cx/textile/web`, each pinned by digest. CI publishes the server image on every push to the `textile` branch, tagged `sha-<commit>`. The web image's `web.Dockerfile` reaches `textile` with mia-cx/textile#72; until then, `web.yaml` pins a dispatched CI build of that PR's branch. To deploy a newer build, copy the digest from that run's summary, or `docker buildx imagetools inspect ghcr.io/mia-cx/textile/<image>:sha-<commit>`, into the manifests that run it.

One host, `textile.cx`, serves both, through two routes. Mesh devices in `svc-textile` resolve it to the private Traefik; everyone else resolves it to the public one.

| Route                          | Central's paths                                                                                                                                                      | Everything else |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| Public (`textile-public`)      | `/authorize` and `/auth/discord/callback` only                                                                                                                       | the website     |
| Private (`textile`, mesh-only) | all of them: `/mcp`, `/voice`, `/register`, `/authorize`, `/token`, `/auth/discord/`, the OAuth discovery documents under `/.well-known/`, `/workflows/`, `/health/` | the website     |

The public route answers 404 for central's other paths and never forwards them. The browser needs only two central paths to sign in: `/authorize` shows central's consent page and takes its form, and Discord returns to `/auth/discord/callback`. The website registers and redeems codes server-side through central's Service, which central's NetworkPolicy allows. So there is one deployment, one login, and one Discord redirect. The public route keeps its requests out of the shared access logs, because the site's session cookie holds a central access token.

Backups use the [Barman Cloud plugin](../cnpg-barman-cloud/README.md): WAL is archived continuously and a base backup runs weekly, Sundays at 03:00 UTC, kept 14 days, in bucket `textile-backups`. RustFS lives on the same cluster, so backups are not off-site yet.

## Before the first sync

1. Run `scripts/bootstrap-textile.sh` from a machine whose kubectl reaches olympus. It walks through the Discord redirect URI and client secret, the allowlist, and generates the other keys, creating these Secrets in `textile`:

   | Secret              | Keys                                                            | Read by                                                                                            |
   | ------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
   | `textile-oauth`     | `DISCORD_OAUTH_CLIENT_SECRET`, `DISCORD_OAUTH_ALLOWED_USER_IDS` | central; bot hosts read the allowlist                                                              |
   | `textile-crypto`    | `OAUTH_ENCRYPTION_KEY`                                          | central                                                                                            |
   | `textile-bot-hosts` | `BOT_HOST_SECRET`                                               | both tiers                                                                                         |
   | `textile-vault`     | `TOKEN_VAULT_KEY`                                               | bot hosts. Its copies in iCloud Keychain and offline are the only way to read a restored database. |
   | `textile-rustfs`    | `RUSTFS_ACCESS_KEY`, `RUSTFS_SECRET_KEY`                        | RustFS and the database's backups                                                                  |
   | `textile-web`       | `SESSION_KEY`                                                   | the website, which seals its sign-in cookies with it                                               |

   CloudNativePG creates `textile-db-app`, whose `uri` the bot hosts use.

2. In Cloudflare, point `textile.cx` at olympus the way `tac.caelest.is` is: a CNAME at the apex to `yggdrasil.mia.cx`, DNS only, not proxied, so the public Traefik terminates TLS with this app's certificate.
3. In the Discord Developer Portal, the Textile application (`1162037890742759424`) needs the redirect `https://textile.cx/auth/discord/callback`. The wizard opens the page.
4. Give the mesh a way in, as for every row in [the private Traefik's table](../traefik-internal/README.md#per-service-shape): add yourself to `svc-textile` in Authentik (`role-admin` includes it) and sign in to NetBird again so the group arrives. Then create NetBird policy `textile` (source `svc-textile`, destination `res-textile`, unidirectional TCP 443) and DNS zone `textile.cx` (distribution groups `svc-textile` and `textile-clients-hephaestus`, search domain off) with an apex A record to `10.43.0.155`. Peers keep their old DNS until they reconnect (`netbird down && netbird up`). That zone answers every name under `textile.cx` on those peers, so give it a record for any other `textile.cx` name they use.
5. Decide whether search engines may index the site. The website, not this deployment, sets that: `apps/web/src/hooks.server.ts` and `apps/web/src/routes/robots.txt/+server.ts` in mia-cx/textile ask crawlers to stay out on every origin except `https://textile.cx`. Here the origin is `https://textile.cx`, so the site sends no `X-Robots-Tag: noindex` and its robots.txt allows crawling. To keep the closed alpha out of search, change those files in the Textile repo and deploy a new web image.
6. cert-manager issues the certificate by DNS-01 through Cloudflare, so `textile.cx` must be a zone that the `cloudflare-api-token` Secret in `cert-manager` can edit.

Merging deploys: ArgoCD creates the plugin (`cnpg-barman-cloud`), the `longhorn-local` StorageClass (`k3s-base`), the private route's entrypoint (`traefik-internal`), and this app.

Moving the running deployment from `staging.textile.cx` needs steps 2 to 5 before the merge, since central then answers only `textile.cx`. Afterwards, delete the `staging.textile.cx` DNS zone in NetBird and its Discord redirect, and sign MCP clients in again at `https://textile.cx/mcp`: central's issuer changes, so logins from the old host stop working.

## Verify

```sh
kubectl -n textile get cluster textile-db            # 2 instances, "Cluster in healthy state"
kubectl -n textile get pods -o wide                  # bot hosts, website pods, and database instances on different nodes
kubectl -n textile get backup                        # the immediate backup reaches "completed"
kubectl -n textile get cluster textile-db \
  -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}'   # True
kubectl -n textile logs statefulset/textile-bot-host | head   # "discord-mcp bot-host listening"
curl -sf https://textile.cx/health/ready             # from a mesh device in svc-textile: 200
# The public route, reached from the LAN at the public Traefik's address:
PUBLIC=textile.cx:443:10.0.128.2
curl -s --resolve $PUBLIC -o /dev/null -w '%{http_code}\n' https://textile.cx/            # 200, the website
curl -s --resolve $PUBLIC -o /dev/null -w '%{http_code}\n' https://textile.cx/authorize   # 400, central refusing an empty request
for path in /mcp /voice /register /token /health/ready /workflows/x \
  /.well-known/oauth-authorization-server /.well-known/oauth-protected-resource/mcp; do
  curl -s --resolve $PUBLIC -o /dev/null -w "%{http_code} $path\n" "https://textile.cx$path"   # 404 for each
done
```

Sign in to the website at `https://textile.cx/access`, once from a mesh device and once off the mesh: it goes through central and Discord and ends on "You're in". That proves both routes reach central and that `textile-web` holds a working `SESSION_KEY`.

Then, from a mesh device, sign in with `node scripts/login.mjs https://textile.cx/mcp` from the Textile repo, call any tool with a test bot's token, and watch the bot come online in Discord. It goes offline 24 hours after the last call.

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
