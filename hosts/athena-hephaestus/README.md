# Hephaestus

The development VM runs at `10.0.3.2`. Its primary and Repair NetBird clients
use separate identities, state, sockets and UDP ports.

## Primary mesh

The primary client is NetBird 0.79.0, installed at `/usr/local/bin/netbird`
and supervised by the enabled `netbird.service`. It uses normal kernel
networking on `wt0`, UDP 51820, and the primary management server at
`https://netbird.mia.cx`. The peer is `hephaestus.netbird.mia.cx`.

This machine enrolls through a one-use setup key, never SSO, so it does not
inherit Mia's human-device permissions or AdGuard assignment. Its API-issued
groups grant:

- `cpa-clients-hephaestus`: policy `hephaestus-cpa`, unidirectional TCP 443 to
  `res-cliproxyapi` only.
- `t3-fleet`: policy `t3-fleet`, all traffic in both directions between fleet
  hosts (with Pegasus), for the T3 Code fleet.

The client disables server routes and receives no Internet exit route. It
manages DNS in resolv.conf mode: NetBird's resolver answers
`*.netbird.mia.cx` peer names and forwards everything else to the original
public resolvers, saved in `/etc/resolv.conf.original.netbird`. An explicit
`/etc/hosts` entry maps `cpa.mia.cx` to the pinned private ingress Service at
`10.43.0.131`, preserving the canonical HTTPS name for shell clients.

The independent, unprivileged `netbird-repair.service` remains on UDP 51821.
Its installation and recovery contract live in [repair-clients](../repair-clients/README.md).

## T3 Code

The user unit `t3code.service` runs `t3 serve` on `0.0.0.0:3773`.

`t3-fleet` hosts reach it at `https://hephaestus.netbird.mia.cx`. The user
unit `caddy-t3.service` terminates TLS there and proxies to `127.0.0.1:3773`:
Caddy (`~/.local/bin/caddy`, built with `caddy-dns/cloudflare`) obtains a
Let's Encrypt certificate through Cloudflare DNS-01, with a mia.cx DNS-edit
token in `~/.config/caddy/cloudflare.env` (mode 0600). Binding 443 as the
user needs `sudo setcap cap_net_bind_service=+ep ~/.local/bin/caddy`, again
after every Caddy upgrade. Pegasus runs the same Caddyfile under the launch
agent `cx.mia.caddy-t3`.

Mesh peers in `agent-grok` reach only the MCP endpoint, at
`https://t3.yggdrasil.mia.cx/mcp`, through the private Traefik
(`argocd/t3code`). Issue their token here, and revoke it with
`t3 auth session revoke`. T3 accepts MCP bearer tokens only with subject
`mcp-client`:

```sh
t3 auth session issue --label grok-bot --ttl 30d --subject mcp-client \
  --scope orchestration:read --scope orchestration:operate --token-only
```

## Agent clients

Mia's local commands are:

```sh
claude-cpa
codex-cpa
```

Both wrappers live in `~/.local/bin` and read the client key from
`~/.config/cpa/api-key`, mode 0600. No management key is needed on this host.
Ordinary `claude` and `codex` commands retain their existing configuration.

`claude-cpa` sets `ANTHROPIC_BASE_URL=https://cpa.mia.cx`, supplies the client
key as `ANTHROPIC_AUTH_TOKEN`, enables gateway model discovery, and selects
`claude-opus-5-5` with high effort. It clears `ANTHROPIC_API_KEY` for that
invocation.

`codex-cpa` supplies `CPA_API_KEY` and selects the `cpa` profile. Codex 0.163.0
loads that profile from `~/.codex/cpa.config.toml`. It uses the Responses API
at `https://cpa.mia.cx/v1` with `gpt-6.1-sol`; reasoning effort remains high
through the existing base configuration.

## Verification

On 2026-10-21, both wrappers returned `CPA_OK` through real provider requests.
Keeper's authenticated overview confirmed recorded requests and token usage.
CPA rejected unauthenticated model listing with 401. The unrelated private
canary destination timed out. The primary client selected only the CPA
`10.43.0.131/32` route; both NetBird services remained active, with the original
default gateway and `/etc/resolv.conf` intact.

Routine checks:

```sh
netbird status
netbird networks ls
systemctl is-active netbird netbird-repair
curl --fail https://cpa.mia.cx/healthz
```

Stopping or removing the primary client does not disable the separate Repair
service. Remove the machine policy or its group membership to revoke CPA
network access. Remove the corresponding client key in CPA to revoke its API
credential.
