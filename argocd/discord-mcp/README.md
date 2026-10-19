# Discord MCP ingress

`https://discord.mia.cx/mcp` reaches the existing Docker instance on Athena.
Traefik uses its default wildcard certificate and forwards HTTP through the
`discord-mcp` Service to `10.0.3.2:3000`. A systemd user socket on Athena relays
that address to Docker's `127.0.0.1:3000` listener without restarting the stack.

The application authenticates MCP clients with its own PATs or configured OIDC.
Discord bot tokens belong in the server configuration, not the client bearer
header. The route has no interactive forward-auth middleware, so MCP clients
and signed Discord requests can reach the application's authentication checks.

## Bootstrap and recovery

Install the two units from `hosts/athena-hephaestus/` into Mia's
`~/.config/systemd/user/` on Athena, then run:

```sh
systemctl --user daemon-reload
systemctl --user enable --now discord-mcp-proxy.socket
```

User lingering must remain enabled so the listener starts without a login.
The socket binds only Athena's LAN address; Docker keeps its loopback binding.

From the repository root, bootstrap the namespace and backend:

```sh
kubectl create namespace discord-mcp --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f argocd/discord-mcp/backend.yaml
kubectl apply -f argocd/_apps/discord-mcp.yaml
```

ArgoCD reconciles the Service and IngressRoute from `main`. Its global resource
exclusions skip EndpointSlices, so explicitly reapply `backend.yaml` when
rebuilding the namespace or changing the backend address. The checked-in slice
is the recovery source; do not widen ArgoCD's shared exclusions for this route.

DNS points `discord.mia.cx` at the existing public Traefik ingress. No DNS
changes or application image upgrades are part of this deployment.

## Verify

```sh
systemctl --user status discord-mcp-proxy.socket --no-pager
curl --fail https://discord.mia.cx/health/ready
curl -i -H 'Accept: application/json, text/event-stream' https://discord.mia.cx/mcp
```

Readiness returns HTTP 200. MCP without a valid application credential returns
HTTP 401. To check ingress before public DNS propagates, add
`--resolve discord.mia.cx:443:10.0.128.2` to either curl command.
