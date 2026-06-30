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
MS365_MCP_ALLOWED_SCOPES=User.Read Mail.Read Calendars.Read Contacts.Read
```

That keeps access delegated to the signed-in user's own Outlook data and avoids shared mailbox / tenant directory / app-only mail access.

## Known OAuth routing note

Public ingress intentionally exposes only `/authorize`. Hermes uses the private kube-vip service for `/mcp`, OAuth metadata, and `/token`, so those endpoints are not browser/public routes.
