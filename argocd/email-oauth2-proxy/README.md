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

The Entra app must have the Office 365 Exchange Online **Application** permission `SMTP.SendAsApp` with admin consent. The proxy uses OAuth client credentials (`oauth2_flow = client_credentials`), so no browser redirect URI or first interactive OAuth authorization is required.

In Exchange Online, register the Entra service principal and grant it access to the sender mailbox, for example:

```powershell
Connect-ExchangeOnline
New-ServicePrincipal -AppId '<application-client-id>' -ObjectId '<enterprise-application-object-id>' -DisplayName 'email-oauth2-proxy'
$sp = Get-ServicePrincipal -Identity 'email-oauth2-proxy'
Add-MailboxPermission -Identity 'noreply@mia.cx' -User $sp.Identity -AccessRights FullAccess
Set-CASMailbox noreply@mia.cx -SmtpClientAuthenticationDisabled $false
```

## Consumer settings

Use this service from in-cluster apps:

- Host: `email-oauth2-proxy.email-oauth2-proxy.svc.cluster.local`
- Port: `587`
- Username: Microsoft mailbox, e.g. `noreply@mia.cx`
- Password: choose a stable proxy password on the first successful SMTP login, then reuse that same password for every consumer. The proxy uses it to encrypt cached OAuth tokens; it is not the Microsoft account password or Entra client secret.
- TLS/STARTTLS to proxy: disabled

Examples:

- Authentik: `authentik.email.host` to the service host, `port: 587`, `use_ssl: false`, `use_tls: false`.
- Vaultwarden: `SMTP_HOST` to the service host, `SMTP_PORT=587`, `SMTP_SECURITY=off`, `SMTP_USERNAME`/`SMTP_PASSWORD` as above.
