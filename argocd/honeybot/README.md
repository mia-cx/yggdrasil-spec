# Honeybot

Argo CD deploys the Honeybot `v1.1.0` Helm chart from the upstream repository.
The bot has no inbound service. It connects to Discord and model providers over
the cluster's normal outbound network path.

Create the namespace and externally managed Secret before the first sync:

```bash
kubectl create namespace honeybot --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic honeybot-secrets -n honeybot \
  --from-literal=DISCORD_TOKEN="$DISCORD_TOKEN" \
  --from-literal=OPENROUTER_API_KEY="$OPENROUTER_API_KEY" \
  --from-literal=API_KEY_ENCRYPTION_KEY="$API_KEY_ENCRYPTION_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
```

`DISCORD_TOKEN` is required. `OPENROUTER_API_KEY` supplies the deployment-wide
model provider default. Generate `API_KEY_ENCRYPTION_KEY` once with
`openssl rand -base64 32`, then keep it stable so stored guild keys remain
decryptable.

The release runs as one replica with a `Recreate` strategy and stores its SQLite
database and evidence files on the `honeybot-data` Longhorn PVC.
