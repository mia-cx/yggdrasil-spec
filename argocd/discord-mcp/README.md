# Discord MCP deployment

The native `discord-mcp` Deployment runs the Discord OAuth relay from
`mia-cx/discord-mcp` main. Its image is pinned by digest in
`deployment.yaml`. The `discord-mcp-relay` Service selects its pod.

## Cutover state

The public IngressRoute targets the native `discord-mcp-relay` Service.
The OAuth credentials are saved and the deployment is Ready. Public health,
OAuth discovery, and unauthenticated MCP challenges verify the cutover.
The hostname and existing Traefik wildcard certificate are unchanged.

Access logging is disabled for this route. Shared Traefik logging retains request
headers, which would otherwise persist OAuth and bot credentials. Keep this
route-local override when updating the service; other routes are unaffected.

The old Athena Docker backend remains intact but receives no public traffic.
Do not restore its PAT/OIDC route without an explicit recovery decision.

## Namespace secrets

Secrets live outside Git in namespace `discord-mcp`:

| Secret               | Keys                                                                                       | Owner                                                                                                            |
| -------------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `discord-mcp-oauth`  | `DISCORD_OAUTH_CLIENT_ID`, `DISCORD_OAUTH_CLIENT_SECRET`, `DISCORD_OAUTH_ALLOWED_USER_IDS` | Enter application credentials using the setup wizard; sync accepted Team members explicitly for the access list. |
| `discord-mcp-crypto` | `OAUTH_ENCRYPTION_KEY`                                                                     | Generated once during deployment; preserve it across restarts and upgrades.                                      |

Only the OAuth client secret needs hidden human input. The encryption key is
32 random bytes encoded as base64. Changing it invalidates issued logins.
Neither Secret contains an agent's Discord bot token.

The live access list includes accepted members of the OAuth application's Discord
developer Team and additional accounts Mia explicitly approves. Check the
application ID and accepted membership for Team updates, preserving separately
approved accounts. Store only user IDs in the allowlist key, never the lookup bot
token. Repeat the sync after Team changes and restart the Deployment. The relay
enforces the list for new logins and existing credentials.
An empty list denies everyone; never unset it or use `*` as a sync-failure fallback.

In the existing Discord application, open OAuth2 and save this exact redirect:

```text
https://discord.mia.cx/auth/discord/callback
```

Keep other redirects that application already uses. The local login helper's
loopback callback is registered with the relay, not with Discord.

The workload references the Secrets through explicit `secretKeyRef` entries.
On first setup, kubelet starts the pending container once the missing OAuth
Secret appears. Later secret rotations require a deployment restart.
Apply Secret updates through stdin with server-side apply, without copying
values into command arguments or last-applied annotations.

## Native workload

Use one replica and `Recreate` upgrades. Authorization-code replay protection
is process-local; unfinished login attempts must restart after pod replacement.
Issued logins survive because the encryption key remains in Kubernetes.

The pod runs as unprivileged UID 10001 with a read-only root filesystem, no
service-account token, no added capabilities, and no data volumes.

```sh
kubectl -n discord-mcp get deployment,pods,svc
kubectl -n discord-mcp rollout status deployment/discord-mcp
```

## Retained Athena backend

`backend.yaml` retains the old selectorless Service and manual EndpointSlice
for an explicit recovery decision. ArgoCD excludes EndpointSlices globally.
Do not change the shared exclusion for this application.

The two proxy units in `hosts/athena-hephaestus/` still forward Athena's LAN
address to its loopback-only Docker listener. The old stack and its data remain
untouched during this native deployment. It uses PAT/OIDC authentication rather
than the new relay's Discord OAuth and per-request bot headers.

## Public verification

```sh
curl --fail https://discord.mia.cx/health/ready
curl -i https://discord.mia.cx/.well-known/oauth-protected-resource/mcp
curl -i -H 'Accept: application/json, text/event-stream' https://discord.mia.cx/mcp
```

After cutover, health and metadata return HTTP 200. MCP without OAuth returns
HTTP 401 with the protected-resource metadata URL in `WWW-Authenticate`.
Before public DNS is usable, add `--resolve discord.mia.cx:443:10.0.128.2`.
