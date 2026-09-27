# netbird-sync

Hourly CronJob that aligns each Hecate user's NetBird group membership with
their effective service permissions. It reads the permission claim through
the Authentik scope-mapping test endpoint — the same code path sign-in uses —
and updates only `jwt`-issued `auto_groups` via the NetBird Management API.
It never creates groups and never touches non-Hecate (local, service) users.

`DRY_RUN` ships as `"true"` in `cronjob.yaml`: the job logs its plan and
writes nothing. Flip to `"false"` once a dry-run log looks right.

## Secrets

One Secret, `netbird-sync` in namespace `netbird-sync`, not in Git:

| Key               | Source                                                       |
| ----------------- | ------------------------------------------------------------ |
| `netbird-token`   | PAT of NetBird service user `netbird-sync` (role admin)      |
| `authentik-token` | Same value as `authentik/netbird-sync-authentik` key `token` |
| `smtp-password`   | `authentik/authentik-secrets` key `email-password`           |
| `alert-to`        | The alert recipient address                                  |

Recreate (values via files/stdin, never argv):

```bash
# Authentik token — also wired into the blueprint via values.yaml
openssl rand -hex 32 > /tmp/ak-token
kubectl --context default -n authentik create secret generic \
  netbird-sync-authentik --from-file=token=/tmp/ak-token

# NetBird service user + PAT (365 days), using the admin PAT
USER_ID=$(curl -sf -H "Authorization: Token $ADMIN_PAT" \
  -H 'Content-Type: application/json' https://netbird.mia.cx/api/users \
  -d '{"name":"netbird-sync","role":"admin","is_service_user":true,"auto_groups":[]}' \
  | jq -r .id)
curl -sf -H "Authorization: Token $ADMIN_PAT" -H 'Content-Type: application/json' \
  "https://netbird.mia.cx/api/users/$USER_ID/tokens" \
  -d '{"name":"netbird-sync","expires_in":365}' | jq -r .plain_token \
  > /tmp/nb-token

kubectl --context default -n authentik get secret authentik-secrets \
  -o jsonpath='{.data.email-password}' | base64 -d > /tmp/smtp-pass

kubectl --context default -n netbird-sync create secret generic netbird-sync \
  --from-file=netbird-token=/tmp/nb-token \
  --from-file=authentik-token=/tmp/ak-token \
  --from-file=smtp-password=/tmp/smtp-pass \
  --from-literal=alert-to='<alert recipient>'
rm /tmp/ak-token /tmp/nb-token /tmp/smtp-pass
```

## Manual run

```bash
kubectl --context default -n netbird-sync \
  create job --from=cronjob/netbird-sync sync-manual-$(date +%s)
kubectl --context default -n netbird-sync logs -l job-name=<name>
```

## PAT rotation

The NetBird PAT expires 365 days after creation. The failure email is the
signal: mint a new PAT for the same service user and update the
`netbird-token` key (same command as above).

## Alerting

Run state lives in ConfigMap `netbird-sync-state` (namespace `netbird-sync`),
created by the job and deliberately not in Git — ArgoCD would revert it. On
the first failing run one email goes out through `email-oauth2-proxy`; on the
first healthy run after failures, one recovery email. No repeat noise.
