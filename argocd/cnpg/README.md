# CloudNativePG operator

ArgoCD installs the CloudNativePG operator from the upstream release manifest at the tag in `kustomization.yaml`. The database `Cluster`s stay in their own apps (`caelestis`, `immich`, `open-wearables`, `pelican`).

An operator upgrade restarts every database `Cluster` and ends each one with a switchover. Bump the tag in a PR of its own, after reading the release notes for that version.

## Adopting the hand install

Operator 1.30.1 was installed with `kubectl apply --server-side` before this Application existed. The Application declares the same manifest, so the first sync takes ownership in place. On 2026-10-31, a server-side dry run of that manifest against the live cluster showed no differences. Argo adds only its `argocd.argoproj.io/tracking-id` annotation to each object's own metadata, not to pod templates. The operator pod does not restart, and no `Cluster` is touched.

The Application syncs manually until the first sync is verified.

1. Check nothing moved since the dry run: `kubectl get deploy -n cnpg-system cnpg-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}'` prints `ghcr.io/cloudnative-pg/cloudnative-pg:1.30.1`.
2. Merge. The `root` app creates the `cnpg` Application, which shows OutOfSync and does nothing on its own.
3. Open the `cnpg` app's diff in ArgoCD. Expect no change except the `argocd.argoproj.io/tracking-id` annotation added to objects' metadata. If anything else differs, stop and don't sync.
4. Sync with prune off.
5. Watch:
   - The app reaches Synced and Healthy.
   - `kubectl get pods -n cnpg-system` shows the same pod with no new restarts.
   - `kubectl get clusters.postgresql.cnpg.io -A` shows every database `Cluster` still healthy, with the same primary.
6. Turn on automated sync with `selfHeal: true` and `prune: false` in a follow-up PR.

### Rolling back

The Application has no `resources-finalizer`, so deleting it leaves the operator, its CRDs and every database in place. Revert the PR, and `root` removes the Application. The leftover tracking annotations are inert.
