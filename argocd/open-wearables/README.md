# Open Wearables

[Open Wearables](https://github.com/the-momentum/open-wearables) stores Apple
Health data from the iPhone and serves it through one API. Agents query it
through the upstream MCP server. It is mesh-only at `https://health.mia.cx`:
the private Traefik serves it on its own destination (see
`argocd/traefik-internal/README.md`), and `svc-open-wearables` grants access.

The portal sends `/api/` to the backend and everything else to the frontend,
so the portal, the phone app and the MCP server all use the one URL.

## Secret

One Secret, `open-wearables` in namespace `open-wearables`, not in Git. The
database password comes from the CNPG Secret `open-wearables-db-app`.

| Key              | Value                                                       |
| ---------------- | ----------------------------------------------------------- |
| `SECRET_KEY`     | Random; signs portal sessions                               |
| `ADMIN_EMAIL`    | Portal login, seeded once while no developer account exists |
| `ADMIN_PASSWORD` | Portal password for that first seed                         |

```bash
set -euo pipefail
openssl rand -base64 48 | tr -d '\n' > /tmp/ow-secret-key
openssl rand -base64 24 | tr -d '\n' > /tmp/ow-admin-password
kubectl --context default create namespace open-wearables \
  --dry-run=client -o yaml | kubectl --context default apply -f -
kubectl --context default -n open-wearables create secret generic open-wearables \
  --from-file=SECRET_KEY=/tmp/ow-secret-key \
  --from-file=ADMIN_PASSWORD=/tmp/ow-admin-password \
  --from-literal=ADMIN_EMAIL='<portal login email>'
rm /tmp/ow-secret-key /tmp/ow-admin-password
```

Read the password back once to sign in, then change it in the portal. Changing
the Secret later does not update an existing account.

## Live NetBird objects

Created through the Management API, like the canary's:

- Policy `open-wearables`: source group `svc-open-wearables`, destination
  group `res-open-wearables`, TCP 443.
- DNS zone `health.mia.cx`: distribution group `svc-open-wearables`, search
  domain off, apex A record `health.mia.cx` → `10.43.0.129`.

`svc-open-wearables` exists in NetBird only after a member signs in once
(access groups are JWT-issued). Peers pick up the new DNS zone after
`netbird down && netbird up`.

## iPhone

1. Install the Open Wearables app. It is in beta: ask for a TestFlight invite
   on the project's Discord.
2. In the portal, create a user, open it, and choose **Connect Mobile App**.
3. In the app, enter `https://health.mia.cx` and the invitation code, then
   grant Health access.

The app syncs in the background whenever the phone is on the mesh.

## Agents

Create an API key in the portal under **Settings → Credentials**. Then add the
MCP server to the agent, pinned to the deployed version:

```json
{
  "mcpServers": {
    "open-wearables": {
      "command": "uvx",
      "args": [
        "--from",
        "git+https://github.com/the-momentum/open-wearables@0.9.0#subdirectory=mcp",
        "start"
      ],
      "env": {
        "OPEN_WEARABLES_API_URL": "https://health.mia.cx",
        "OPEN_WEARABLES_API_KEY": "<api key>"
      }
    }
  }
}
```

The agent's host must be a mesh peer in `svc-open-wearables`.

## Upgrades

Bump both image tags in `backend.yaml` and `frontend.yaml` together, plus the
MCP tag above. The API applies database migrations on start.
