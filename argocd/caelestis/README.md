# TAC Caelestis

- Frontend: https://tac.caelest.is
- Backend for the userscript: https://tac.caelest.is/backend

The upstream Helm chart runs the Bun backend and Node frontend in one pod. A dedicated two-instance
CNPG cluster holds the database. A 20 GiB Longhorn volume holds objects shared by the two containers.
The chart uses one replica with Recreate updates to preserve backend ownership and volume access.

Traefik routes `/backend` directly to the backend and all other paths to the frontend.
The frontend handles its public read-only WebSocket endpoint at `/api/v1/telemetry/live`.
HTTP redirects to HTTPS. The `caelestis-tls` certificate covers `caelest.is` and `*.caelest.is` and renews
through the existing `letsencrypt-cloudflare` issuer.

The Bun backend is version `0.9.5` and the frontend is version `0.7.6`, both on Node.js 24.22.1.
Values pin their Docker Hub manifest digests; the Application pins the chart to release commit
`fa01303415a4e5b89a38ba3e6f8dca06eaed4ac7`. Both Yggdrasil nodes run the amd64 variant.
The images come from [the release run](https://github.com/mia-cx/Caelestis/actions/runs/39637268221).

Provisioning:

1. Publish the tested backend and frontend images and verify anonymous pulls from their registry.
   This deployment's backend image selects Bun.
2. Give the existing Cloudflare token in `cert-manager` Zone Read and DNS Edit access to `caelest.is`.
   The DNS-only `tac.caelest.is` CNAME points to `yggdrasil.mia.cx`.
3. Create `caelestis-server` in namespace `caelestis` with separate random `ADMIN_TOKEN` and
   `CAELESTIS_READ_TOKEN` entries. Keep their values outside Git. CNPG creates its own database credentials.

Use the bootstrap admin token to add this server in the userscript. The frontend receives only the
read-only token. Access is private until an administrator creates invitation tokens.

Back up the PostgreSQL database and object volume together before upgrades, with application writes
stopped. CNPG replication and Longhorn replicas do not replace backups.
