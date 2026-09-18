# Caelestis

One Caelestis server per wplace alliance, all under `caelest.is`. Each alliance is a directory in
`tenants/`; the `caelestis` ApplicationSet turns every directory into an Application named
`caelestis-<name>` in the shared `caelestis` namespace.

Per tenant, one `values.yaml` feeds two charts:

- The upstream Caelestis chart at `deploy/helm/caelestis` runs the Bun backend and Node frontend in one
  pod with a 20 GiB Longhorn object volume. One replica with Recreate updates preserves backend
  ownership and volume access.
- The local `tenant` chart adds a dedicated two-instance CNPG cluster and the Traefik routes:
  `/backend` to the backend, everything else to the frontend, HTTP redirected to HTTPS.

`shared/` holds the wildcard `caelestis-tls` certificate for `caelest.is` and `*.caelest.is` (renewed by
the `letsencrypt-cloudflare` issuer) and the HTTPS redirect middleware.

The Caelestis chart revision is pinned once in `_apps/caelestis.yaml` and applies to every tenant.
Image digests are pinned per tenant.

## Tenants

| Tenant | Frontend                  | Backend                            |
| ------ | ------------------------- | ---------------------------------- |
| tac    | https://tac.caelest.is    | https://tac.caelest.is/backend     |

TAC keeps its original `caelestis-database` cluster name through `tenant.database.name`.

## Adding an alliance

1. Copy `tenants/tac` to `tenants/<name>`. Set `server.name`, `server.origin`, `tenant.host` to
   `<name>.caelest.is`, `server.existingSecret` to `<name>-server`, and the three database entries to
   `<name>-database-rw.caelestis.svc`, `<name>-database-app`, `<name>-database-ca`.
   Remove `tenant.database.name`.
2. Add the DNS-only `<name>.caelest.is` CNAME to `yggdrasil.mia.cx`.
3. Create secret `<name>-server` in namespace `caelestis` with random `ADMIN_TOKEN` and
   `CAELESTIS_READ_TOKEN` entries. Keep the values outside Git. CNPG creates the database credentials.
4. Merge. Use the admin token to add the server in the userscript; the frontend receives only the
   read-only token. Access is private until an administrator creates invitation tokens.

## Removing an alliance

Delete the tenant directory. Prune removes the pod, routes and CNPG cluster; the object PVC and the
`<name>-server` secret remain until deleted by hand. Back up the database and object volume together
first, with writes stopped.

Back up the same way before chart upgrades. CNPG replication and Longhorn replicas do not replace
backups.
