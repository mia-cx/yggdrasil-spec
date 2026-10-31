# Longhorn

ArgoCD installs Longhorn from the upstream `deploy/longhorn.yaml` at the tag in `kustomization.yaml`, with one change: new volumes get 2 replicas, because two nodes can never hold the stock 3. `two-replicas.yaml` sets both places Longhorn reads a replica count from:

- `longhorn-storageclass`, which Longhorn rebuilds the `longhorn` StorageClass from.
- `default-replica-count` in `longhorn-default-setting`, for volumes created without a StorageClass count (`longhorn-static`, the Longhorn UI).

Existing volumes keep their count. Change one with `kubectl patch volumes.longhorn.io -n longhorn-system <pvc-id> --type merge -p '{"spec":{"numberOfReplicas":2}}'`.

Upgrades change the tag in a PR of their own, after reading Longhorn's upgrade notes for that version.

## Adopting the hand install

Longhorn v1.7.3 was installed with `kubectl apply` before this Application existed. The Application declares the same manifest, so the first sync takes ownership in place. A server-side dry run against the live cluster on 2026-10-31 differed in two fields only:

| Object                               | Change                                                 |
| ------------------------------------ | ------------------------------------------------------ |
| ConfigMap `longhorn-default-setting` | adds `default-replica-count: 2`; the live setting is 1 |
| ConfigMap `longhorn-storageclass`    | restores the stock `app.kubernetes.io/*` labels        |

Every other object matched. Argo also adds its `argocd.argoproj.io/tracking-id` annotation to each object's own metadata, not to pod templates, so no pod restarts.

The Application syncs manually until the first sync is verified.

1. Check nothing moved since the dry run: `kubectl get ds -n longhorn-system longhorn-manager -o jsonpath='{.spec.template.spec.containers[0].image}'` prints `longhornio/longhorn-manager:v1.7.3`.
2. Merge. The `root` app creates the `longhorn` Application, which shows OutOfSync and does nothing on its own.
3. Open the `longhorn` app's diff in ArgoCD. Expect the two changes above, plus the `argocd.argoproj.io/tracking-id` annotation added to objects without an `app.kubernetes.io/instance` label, such as the `longhorn-system` Namespace. If anything else differs, stop and don't sync.
4. Sync with prune off.
5. Watch:
   - The app reaches Synced and Healthy.
   - `kubectl get pods -n longhorn-system` shows no new restarts.
   - `kubectl get settings.longhorn.io -n longhorn-system default-replica-count` shows 2.
   - `kubectl get sc longhorn -o jsonpath='{.parameters.numberOfReplicas}'` prints 2.
   - `kubectl get volumes.longhorn.io -n longhorn-system` shows the same robustness as before.
6. Turn on automated sync with `selfHeal: true` and `prune: false` in a follow-up PR.

### Rolling back

The Application has no `resources-finalizer`, so deleting it leaves every Longhorn object in place. Revert the PR, and `root` removes the Application. The leftover tracking annotations are inert. If the replica-count setting must go back to 1, run `kubectl edit cm -n longhorn-system longhorn-default-setting` and remove `default-replica-count`, then set it to 1 in the Longhorn UI.
