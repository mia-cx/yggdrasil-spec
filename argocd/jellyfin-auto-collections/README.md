# Jellyfin-Auto-Collections

CronJob that syncs Jellyfin collections from IMDb, Letterboxd, TSPDT, BFI, and other list sources. No UI — runs on schedule (default 04:00 daily).

**Upstream:** [ghomasHudson/Jellyfin-Auto-Collections](https://github.com/ghomasHudson/Jellyfin-Auto-Collections)

## Prerequisites

Create a Secret in the `media` namespace with your Jellyfin API credentials:

```bash
kubectl create secret generic jellyfin-auto-collections-secrets \
  --namespace media \
  --from-literal=JELLYFIN_API_KEY='your-api-key' \
  --from-literal=JELLYFIN_USER_ID='your-jellyfin-user-id'
```

- **API key:** Jellyfin Dashboard → Advanced → API Keys.
- **User ID:** From the URL when viewing your user in the Dashboard (UUID).

Optional: add `JELLYFIN_SERVER_URL` to the secret to override the default `http://jellyfin.media:8096`.

## Customising lists

Edit `configmap.yaml` and adjust the `plugins` section (enable/disable sources, change `list_ids`). Then re-apply or let Argo CD sync.
