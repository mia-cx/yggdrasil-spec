# email-oauth2-proxy

SMTP proxy for apps that only support username/password SMTP. It accepts plain SMTP on the standard submission port `587`, then sends through Microsoft SMTP with OAuth2.

## Required secret

Create this before syncing the Argo CD app:

```sh
kubectl create namespace email-oauth2-proxy
kubectl -n email-oauth2-proxy create secret generic email-oauth2-proxy-secrets \
  --from-literal=microsoft-account='noreply@mia.cx' \
  --from-literal=microsoft-client-id='<entra-application-client-id>' \
  --from-literal=microsoft-client-secret='<entra-client-secret>' \
  --from-literal=microsoft-tenant-id='<tenant-id-or-common>'
```

Register `https://smtproxy.yggdrasil.mia.cx` as a web redirect URI in the Microsoft app registration. Traefik terminates HTTPS, protects the proxy's web endpoint with the shared Authentik middleware, and forwards to port `8080`.

## First OAuth authorization

1. Start an SMTP port-forward:
   ```sh
   kubectl -n email-oauth2-proxy port-forward svc/email-oauth2-proxy 587:587
   ```
2. Trigger one SMTP login against the proxy using the Microsoft account as the username and your chosen proxy password as the password. Use no SMTP TLS/STARTTLS between the client and proxy. With `swaks`:
   ```sh
   swaks --server 127.0.0.1 --port 587 --auth LOGIN \
     --auth-user noreply@mia.cx --auth-password '<proxy-password>' \
     --quit-after AUTH
   ```
3. Open the authorization URL from the pod logs, finish Authentik/Microsoft login, and let it redirect to `https://smtproxy.yggdrasil.mia.cx`.

The OAuth token cache is stored in `email-oauth2-proxy-data` at `/data/credstore.config`. The SMTP password used during authorization is the password consumers must keep using.

## Consumer settings

Use this service from in-cluster apps:

- Host: `email-oauth2-proxy.email-oauth2-proxy.svc.cluster.local`
- Port: `587`
- Username: Microsoft mailbox, e.g. `noreply@mia.cx`
- Password: the proxy password used during first authorization
- TLS/STARTTLS to proxy: disabled

Examples:

- Authentik: `authentik.email.host` to the service host, `port: 587`, `use_ssl: false`, `use_tls: false`.
- Vaultwarden: `SMTP_HOST` to the service host, `SMTP_PORT=587`, `SMTP_SECURITY=off`, `SMTP_USERNAME`/`SMTP_PASSWORD` as above.
