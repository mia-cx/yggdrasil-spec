# netbird-sync

Hourly CronJob that aligns each Hecate user's NetBird group membership with
their effective service permissions. It reads the permission claim through
the Authentik scope-mapping test endpoint — the same code path sign-in uses —
and updates only `jwt`-issued `auto_groups` via the NetBird Management API.
It never creates groups and never touches non-Hecate (local, service) users.

`DRY_RUN` is `"false"` in `cronjob.yaml`. Set it to `"true"` to log the plan
without writing anything, for example after changing the matching logic.

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
set -euo pipefail

# Authentik token — also wired into the blueprint via values.yaml
openssl rand -hex 32 | tr -d '\n' > /tmp/ak-token
kubectl --context default -n authentik create secret generic \
  netbird-sync-authentik --from-file=token=/tmp/ak-token

# NetBird service user + PAT (365 days), using the admin PAT
USER_ID=$(curl -sf -H "Authorization: Token $ADMIN_PAT" \
  -H 'Content-Type: application/json' https://netbird.mia.cx/api/users \
  -d '{"name":"netbird-sync","role":"admin","is_service_user":true,"auto_groups":[]}' \
  | jq -r .id)
curl -sf -H "Authorization: Token $ADMIN_PAT" -H 'Content-Type: application/json' \
  "https://netbird.mia.cx/api/users/$USER_ID/tokens" \
  -d '{"name":"netbird-sync","expires_in":365}' | jq -j .plain_token \
  > /tmp/nb-token

kubectl --context default -n authentik get secret authentik-secrets \
  -o jsonpath='{.data.email-password}' | base64 -d > /tmp/smtp-pass

test -s /tmp/ak-token && test -s /tmp/nb-token
kubectl --context default -n netbird-sync create secret generic netbird-sync \
  --from-file=netbird-token=/tmp/nb-token \
  --from-file=authentik-token=/tmp/ak-token \
  --from-file=smtp-password=/tmp/smtp-pass \
  --from-literal=alert-to='<alert recipient>'
rm /tmp/ak-token /tmp/nb-token /tmp/smtp-pass
```

Create both Secrets before ArgoCD syncs the authentik app. If
`authentik/netbird-sync-authentik` is created or rotated later, restart so
the pods pick up the env — a missing or stale `NETBIRD_SYNC_AUTHENTIK_TOKEN`
makes the blueprint's `!Env` fail:

```bash
kubectl --context default -n authentik rollout restart \
  deploy/authentik-worker deploy/authentik-server
```

## Manual run

```bash
kubectl --context default -n netbird-sync \
  create job --from=cronjob/netbird-sync sync-manual-$(date +%s)
kubectl --context default -n netbird-sync logs -l job-name=<name>
```

## Add a TV

A TV is a Hecate service account linked to a NetBird peer; the job grants
the peer `owner-groups ∩ tv-allowlist` at each run. A TV needs no
`netbird-enroll` permission: per-service DNS zones are distributed to the
`svc-*` group itself, not the enrolling user.

1. In Hecate, create a service account `tv-<room>`; make it a member of the
   allowlist groups (e.g. `svc-jellyfin`); set attribute
   `netbird_tv_owner` to the owner's Authentik username.
2. Mint a one-off setup key (reaches nothing until linked):

   ```bash
   curl -sf -H "Authorization: Token $ADMIN_PAT" \
     -H 'Content-Type: application/json' \
     https://netbird.mia.cx/api/setup-keys \
     -d '{"name":"tv-<room>","type":"one-off","expires_in":86400,"auto_groups":[],"usage_limit":1}' \
     | jq -r .key
   ```

3. Enroll the TV's NetBird app with management URL `https://netbird.mia.cx`
   and that key.
4. Copy the peer id from NetBird and set attribute `netbird_peer_id` on the
   service account.
5. Access starts at the next run, or trigger one:

   ```bash
   kubectl --context default -n netbird-sync \
     create job --from=cronjob/netbird-sync sync-manual-$(date +%s)
   ```

Removal: deactivate or delete the TV service account, or revoke the owner's
permission — the next run strips the peer's jwt groups. Deleting the
service-account attributes unlinks the peer the same way.

A reinstalled TV enrolls as a new peer with a new id: update
`netbird_peer_id` on the service account. Until then every run fails on the
stale link (and emails once, on the failure edge).

## PAT rotation

The NetBird PAT expires 365 days after creation. The failure email is the
signal: mint a new PAT for the same service user and update the
`netbird-token` key (same command as above).

## Alerting

Run state lives in ConfigMap `netbird-sync-state` (namespace `netbird-sync`),
created by the job and deliberately not in Git — ArgoCD would revert it. On
the first failing run one email goes out through `email-oauth2-proxy`; on the
first healthy run after failures, one recovery email. No repeat noise.
