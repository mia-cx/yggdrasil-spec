---
title: ArgoCD
---

# ArgoCD

## Overview

| Property  | Value                                          |
| --------- | ---------------------------------------------- |
| Type      | K8s                                            |
| Namespace | `argocd`                                       |
| Pattern   | App of Apps                                    |
| Repo      | `git@github.com:mia-cx/yggdrasil-spec.git` |
| Sync      | Automated (prune + self-heal)                  |

GitOps continuous delivery -- automatically syncs all manifests and Helm charts from this repo to the cluster. A root Application watches `argocd/_apps/` and creates all child Applications.

## Prerequisites

- K3s cluster running
- kubectl configured

## Setup

```bash
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.5/manifests/install.yaml
kubectl wait --for=condition=Available -n argocd deployment/argocd-server --timeout=120s
```

The version is pinned so upgrades are deliberate. Server-side apply is required because
the ApplicationSet CRD is too large for kubectl's client-side `last-applied` annotation.

### Upgrade

Review the upstream release notes, update the pinned version above, then apply the same
official manifest server-side and verify every Argo workload:

```bash
kubectl apply --server-side --force-conflicts -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.4.5/manifests/install.yaml
kubectl get pods -n argocd
kubectl get applications -n argocd
```

Argo CD 3.3.1 used a non-idempotent `ln -s` command in the repo-server
`copyutil` init container. If that old pod reinitializes with its `emptyDir` contents
still present, it can crash with `/bin/ln: Already exists`. Recreate the pod to recover,
then backport the idempotent command until the pinned upgrade is applied:

```bash
kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-repo-server
kubectl patch deployment argocd-repo-server -n argocd --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/initContainers/0/args/0","value":"/bin/cp /usr/local/bin/argocd /var/run/argocd/argocd && /bin/ln -sf /var/run/argocd/argocd /var/run/argocd/argocd-cmp-server"}]'
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=180s
```

**CLI (optional):**

```bash
brew install argocd
```

**Get initial admin password:**

```bash
argocd admin initial-password -n argocd
```

### Repo Access

If the repo is private, create a deploy key or access token:

```bash
# Option 1: SSH deploy key
argocd repo add git@github.com:mia-cx/yggdrasil-spec.git \
  --ssh-private-key-path ~/.ssh/argocd_deploy_key

# Option 2: HTTPS token (fine-grained PAT with Contents: Read)
argocd repo add git@github.com:mia-cx/yggdrasil-spec.git \
  --username x-access-token \
  --password ghp_YOUR_TOKEN
```

If the repo is public, ArgoCD can access it without credentials.

### Bootstrap

One command to deploy everything:

```bash
kubectl apply -f argocd/_apps/root.yaml
```

The root Application syncs `argocd/_apps/`, which contains Application manifests for every service. ArgoCD then syncs each child Application from the repo.

## Configuration

### Application Structure

```
argocd/_apps/
  root.yaml             <- App of Apps (bootstrap this one)
  infrastructure.yaml   <- cert-manager, k3s-base, databases, cloudflare-ddns
  traefik.yaml          <- Helm (traefik/traefik) + middlewares + TLS store
  authentik.yaml        <- Helm multi-source (chart + values + IngressRoute)
  nextcloud.yaml        <- Helm multi-source (chart + values + storage + IngressRoute)
  jellyfin.yaml         <- Helm multi-source (chart + values + storage + IngressRoute)
  immich.yaml           <- Helm multi-source (chart + values + NFS + PostgreSQL + IngressRoute)
  vaultwarden.yaml      <- Raw manifests (storage + deployment + IngressRoute)
  pelican.yaml          <- Helm (custom chart) + IngressRoute
  netbird.yaml          <- Raw manifests
```

### Multi-Source Helm Apps

For services using external Helm charts (Authentik, Nextcloud, Jellyfin, Immich), each Application has three sources:

1. **Helm chart** from the upstream chart repo (e.g., `charts.goauthentik.io`)
2. **Git ref** (`$values`) -- makes `values.yaml` from this repo available to the Helm source
3. **Git directory** -- companion manifests (storage, IngressRoute) from the same `argocd/<service>/` directory, excluding values files

Update `values.yaml` in git → ArgoCD detects the change → re-renders the Helm chart with new values → applies.

### Day-to-Day Workflow

**Update a Helm value:** Edit `argocd/<service>/values.yaml`, commit, push. ArgoCD auto-syncs within ~3 minutes.

**Upgrade a chart version:** Edit `targetRevision` in `argocd/_apps/<service>.yaml`, commit, push.

**Add a new service:**

1. Create `argocd/<service>/` with manifests and/or values
2. Create `argocd/_apps/<service>.yaml` with the Application definition
3. Commit and push -- the root Application picks it up automatically

**Force sync:**

```bash
argocd app sync <app-name>
```

**Check status:**

```bash
argocd app list
argocd app get <app-name>
```

### UI Access

Expose the dashboard via IngressRoute or port-forward:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then visit `https://localhost:8080`.

## Important Notes

- **Secrets are NOT in git.** Create them manually before the first sync (see each service's docs for `kubectl create secret` commands).
- **kube-vip is excluded** from ArgoCD -- it's a static pod placed on nodes before K3s installs.
- **Chart versions are pinned** in `argocd/_apps/*.yaml`. Update `targetRevision` when upgrading.
- **Prune is enabled** -- deleting a manifest from git will delete the resource from the cluster.

## Verification

```bash
kubectl get pods -n argocd
argocd app list
```
