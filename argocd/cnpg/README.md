# CloudNativePG operator

ArgoCD installs the CloudNativePG operator from the upstream release manifest at the tag in `kustomization.yaml`. The database `Cluster`s stay in their own apps (`caelestis`, `immich`, `open-wearables`, `pelican`).

An operator upgrade restarts every database `Cluster` and ends each one with a switchover. Bump the tag in a PR of its own, after reading the release notes for that version.

The operator was first installed by hand with `kubectl apply --server-side`. ArgoCD took over those objects in place on 2026-10-31: the first sync only added its `argocd.argoproj.io/tracking-id` annotation, the operator pod kept running, and every `Cluster` kept its primary.

Sync is automated with `selfHeal` and without prune, so dropping an object from the manifest never deletes it from the cluster. The Application has no `resources-finalizer`, so deleting it leaves the operator, its CRDs and every database in place.
