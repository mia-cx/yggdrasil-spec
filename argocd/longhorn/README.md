# Longhorn

ArgoCD installs Longhorn from the upstream `deploy/longhorn.yaml` at the tag in `kustomization.yaml`, with one change: new volumes get 2 replicas, because two nodes can never hold the stock 3. `two-replicas.yaml` sets both places Longhorn reads a replica count from:

- `longhorn-storageclass`, which Longhorn rebuilds the `longhorn` StorageClass from.
- `default-replica-count` in `longhorn-default-setting`, for volumes created without a StorageClass count (`longhorn-static`, the Longhorn UI).

Existing volumes keep their count. Change one with `kubectl patch volumes.longhorn.io -n longhorn-system <pvc-id> --type merge -p '{"spec":{"numberOfReplicas":2}}'`.

## Backups

The `default` BackupTarget points at `nfs://10.0.1.9:/mnt/media/longhorn-backups` on the media NFS share. It is a live setting, not in Git; set it with `kubectl -n longhorn-system patch settings.longhorn.io backup-target --type merge -p '{"value":"nfs://10.0.1.9:/mnt/media/longhorn-backups"}'` on Longhorn 1.7, or on the `default` BackupTarget from 1.8 on. Nothing schedules backups; take one before every upgrade.

## Upgrades

Upgrades go one minor version at a time, each tag change in a PR of its own, after reading Longhorn's upgrade notes for that version:

1. Back up every attached volume, and confirm each node keeps more than `storage-minimal-available-percentage` (25%) free.
2. Merge the tag change and wait for every Longhorn pod to run the new version.
3. Move every volume to the new engine: set `concurrent-automatic-engine-upgrade-per-node-limit` to `3`, wait until no volume reports the old `currentImage`, then set it back to `0`.
4. Check that every attached volume is `healthy` before the next hop.

Longhorn was first installed by hand with `kubectl apply`. ArgoCD took over those objects in place on 2026-10-31. The first sync set `default-replica-count` to 2 (it was 1), restored the stock labels on `longhorn-storageclass` and added Argo's `argocd.argoproj.io/tracking-id` annotations. No pod restarted and no volume changed.

Sync is automated with `selfHeal` and without prune, so dropping an object from the manifest never deletes it from the cluster. The Application has no `resources-finalizer`, so deleting it leaves every Longhorn object and volume in place.
