# Longhorn

ArgoCD installs Longhorn from the upstream `deploy/longhorn.yaml` at the tag in `kustomization.yaml`, with one change: new volumes get 2 replicas, because two nodes can never hold the stock 3. `two-replicas.yaml` sets both places Longhorn reads a replica count from:

- `longhorn-storageclass`, which Longhorn rebuilds the `longhorn` StorageClass from.
- `default-replica-count` in `longhorn-default-setting`, for volumes created without a StorageClass count (`longhorn-static`, the Longhorn UI).

Existing volumes keep their count. Change one with `kubectl patch volumes.longhorn.io -n longhorn-system <pvc-id> --type merge -p '{"spec":{"numberOfReplicas":2}}'`.

Upgrades change the tag in a PR of their own, after reading Longhorn's upgrade notes for that version.

Longhorn was first installed by hand with `kubectl apply`. ArgoCD took over those objects in place on 2026-10-31. The first sync set `default-replica-count` to 2 (it was 1), restored the stock labels on `longhorn-storageclass` and added Argo's `argocd.argoproj.io/tracking-id` annotations. No pod restarted and no volume changed.

Sync is automated with `selfHeal` and without prune, so dropping an object from the manifest never deletes it from the cluster. The Application has no `resources-finalizer`, so deleting it leaves every Longhorn object and volume in place.
