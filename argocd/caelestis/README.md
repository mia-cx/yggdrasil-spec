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

Images and chart come from the Caelestis server release `server-backend-0.9.0-frontend-0.7.0`.
Values pin the GHCR digests of the semantic tags `0.9.0` (Bun backend) and `0.7.0` (frontend); the
Application pins the chart to the same release tag. Both Yggdrasil nodes run the amd64 variant.

Provisioning:

1. Publish the tested backend and frontend GHCR images and make the packages public.
   This deployment's backend image selects Bun.
2. Give the existing Cloudflare token in `cert-manager` Zone Read and DNS Edit access to `caelest.is`.
   The DNS-only `tac.caelest.is` CNAME points to `yggdrasil.mia.cx`.
3. Create `caelestis-server` in namespace `caelestis` with separate random `ADMIN_TOKEN` and
   `CAELESTIS_READ_TOKEN` entries. Keep their values outside Git. CNPG creates its own database credentials.

Use the bootstrap admin token to add this server in the userscript. The frontend receives only the
read-only token. Access is private until an administrator creates invitation tokens.

Back up the PostgreSQL database and object volume together before upgrades, with application writes
stopped. CNPG replication and Longhorn replicas do not replace backups.
