# CloudNativePG Barman Cloud plugin

ArgoCD installs the [Barman Cloud plugin](https://cloudnative-pg.io/plugin-barman-cloud/) from the upstream release manifest at the tag in `kustomization.yaml`, into `cnpg-system` beside the operator. It adds the `ObjectStore` CRD and the plugin Deployment, and uses cert-manager for the TLS between operator and plugin.

A `Cluster` opts in with a `plugins` entry naming `barman-cloud.cloudnative-pg.io` and an `ObjectStore`; `argocd/textile/postgresql.yaml` is the first. Clusters without one are unaffected.

Sync is automated with `selfHeal` and without prune, like the operator's app.
