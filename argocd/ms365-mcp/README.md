# MS365 MCP Server

HTTP MCP endpoint for Microsoft Graph via `@softeria/ms-365-mcp-server`.

## Entra app

Redirect URI for the Hermes OAuth callback:

```txt
https://hermes.mia.cx/mcp-oauth/ms365/callback
```

Optional alias already allowed by the server manifest:

```txt
https://hermes.yggdrasil.mia.cx/mcp-oauth/ms365/callback
```

## Secret

Create the secret out-of-band before syncing the ArgoCD app:

```bash
kubectl create namespace ms365-mcp --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic ms365-mcp-secrets -n ms365-mcp \
  --from-literal=client-id='<entra-application-client-id>' \
  --from-literal=client-secret='<entra-client-secret-value>' \
  --from-literal=tenant-id='<entra-tenant-id>'
```

## Exposure

Only `/authorize` is exposed publicly and it is protected by the existing Authentik Traefik middleware.

`/mcp` stays off public ingress. Hermes should use the private kube-vip LoadBalancer endpoint:

```txt
http://10.0.128.5:3000/mcp
```

## Scope boundary

The deployment sets:

```txt
MS365_MCP_ALLOWED_SCOPES=User.Read Mail.ReadWrite Mail.ReadWrite.Shared Mail.Send Mail.Send.Shared Calendars.ReadWrite Calendars.ReadWrite.Shared Tasks.ReadWrite Tasks.ReadWrite.Shared MailboxSettings.Read MailboxSettings.ReadWrite
```

That keeps access delegated to the signed-in user's own resources plus shared mailboxes, calendars, and task lists they already have access to. Mailbox settings are included so Hermes can create/update Outlook sorting rules after triage patterns stabilize. Tenant directory and contacts scopes stay excluded unless explicitly added later.

## Known OAuth routing note

Public ingress intentionally exposes only `/authorize`. Hermes uses the private kube-vip service for `/mcp`, OAuth metadata, and `/token`, so those endpoints are not browser/public routes.
