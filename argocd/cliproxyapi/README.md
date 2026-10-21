# CLIProxyAPI and usage history

`https://cpa.mia.cx` serves the proxy API and `/management.html` for account
setup. `https://cpa-usage.mia.cx` serves CPA Usage Keeper. Both are private
NetBird destinations, with separate entrypoints and resource groups. The
`svc-cliproxyapi` Hecate permission grants both; `role-admin` inherits it.
The first permission-holding NetBird sign-in creates its JWT-issued group.
Create the matching NetBird policies and DNS zones after that sign-in.

CPA uses normal pod networking, CoreDNS and the cluster's WAN gateway.
There is no NetBird sidecar, default mesh route, upstream proxy, host network,
or public/NodePort Service. Mesh routers carry inbound requests only.

## First install

Run `node scripts/bootstrap-cliproxyapi.mjs` from the repository root before
syncing the ArgoCD application. It creates namespace `cliproxyapi` and Secret
`cliproxyapi-bootstrap`, preserving an existing Secret. Values go to Kubernetes
through stdin; credentials are never committed or passed as command arguments.

| Secret key        | Purpose                                                         |
| ----------------- | --------------------------------------------------------------- |
| `config.yaml`     | First-install config, with generated management and client keys |
| `management-key`  | CPA management login and Keeper's server-side credential        |
| `client-key`      | Initial client API key                                          |
| `keeper-password` | Keeper admin login                                              |

Retrieve a value privately, for example:

```sh
kubectl -n cliproxyapi get secret cliproxyapi-bootstrap \
  -o jsonpath='{.data.keeper-password}' | base64 -d
```

Use `.data.management-key` or `.data.client-key` for the other logins.
Subsequent keys and account credentials are managed through CPA.

## Persistent state

CPA seeds `/data/config.yaml` once from the bootstrap Secret. Management UI
edits, refreshed OAuth credentials, plugins and the Cursor bridge cache live on
`cliproxyapi-data`. ArgoCD does not overwrite them. Changing `config.example`
affects fresh installations only. Management-key rotation must update the live
CPA config and Keeper's Secret together, followed by a Keeper restart.

Keeper stores SQLite, migrations and daily backups on `keeper-data`. Daily
backups retain seven days on the same volume; they do not replace an off-volume
backup. Both Deployments use one replica and `Recreate` for their RWO volumes.

API and Keeper logins remain enabled inside the mesh. Traefik access logging
is disabled on these routes because the shared log format retains headers.
Full request/response logging stays disabled in CPA.

## Providers

Claude Code, Codex and Devin use CPA's native account setup. Add the accounts
in `/management.html`; this deployment imports no desktop credentials.

Cursor uses the community [`auth-cursor` plugin](https://github.com/UNICKCHENG/cliproxyapi-plugins/tree/main/auth-cursor).
Its store is configured and `/data/plugins` and `/data/cache` are persistent.
The initial deployment installs `auth-cursor` 2.1.1 through that store; a fresh
installation needs the same step before importing a Cursor dashboard API key.
Cursor traffic uses its SDK agent bridge; it is not a native inference API.
The plugin's `proxy-url` is empty so it uses direct cluster egress too.

## Checks

```sh
kubectl -n cliproxyapi get deploy,pods,pvc,certificate
kubectl -n cliproxyapi rollout status deploy/cliproxyapi
kubectl -n cliproxyapi rollout status deploy/cpa-usage-keeper
```

An authorized NetBird device receives `10.43.0.131` for `cpa.mia.cx` and
`10.43.0.132` for `cpa-usage.mia.cx`. `/healthz` and Keeper's `/readyz`
return 200. Unauthenticated `/v1/models`, CPA management, and Keeper's
`/api/v1/usage/overview` return 401. Public Traefik returns 404 for both names;
ordinary LAN clients and unrelated pods cannot reach either private backend.

Keeper uses CPA's authenticated usage subscription on port 8317, without an
additional Redis server. Usage statistics are enabled, with a one-hour
in-memory backfill window; upstream account logins and a real request are needed
to validate provider usage and quotas.
