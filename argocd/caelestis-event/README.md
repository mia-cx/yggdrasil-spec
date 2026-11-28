# Caelestis Event

- Frontend: https://event.caelest.is
- Backend for the userscript: https://event.caelest.is/backend

A Caelestis server for Wplace events, separate from the main server at `caelest.is`. It shares no
database, storage, or tokens with it, so painters invited here see only this server's templates.

The upstream Helm chart runs the Bun backend and Node frontend in one pod, with SQLite and template
objects on one 5 GiB Longhorn volume. Traefik routes `/backend` to the backend and everything else to
the frontend; HTTP redirects to HTTPS. The `caelestis-event-tls` certificate renews through the
`letsencrypt-cloudflare` issuer.

Values pin backend 1.7.0 and frontend 1.1.0 by Docker Hub digest; the Application pins the chart to
their release commit `0ea825203384c35e7efa2cbe2ccc0ef8dda40b25`.

Provisioning:

1. The DNS-only `event.caelest.is` CNAME points to `yggdrasil.mia.cx`.
2. Create `caelestis-server` in namespace `caelestis-event` with separate random `ADMIN_TOKEN` and
   `CAELESTIS_READ_TOKEN` entries. Keep their values outside Git.

Add the server in the userscript with the admin token, then create access tokens for the painters you
invite. Set `server.openAccess: true` in `values.yaml` to let anyone with the address join instead.

Back up the volume before upgrades; Longhorn replicas do not replace backups. Remove the Application
and its namespace when the event ends.
