# Textile on Google Cloud

The Google Cloud half of Textile production: bot hosts and their CloudNativePG database on GKE Autopilot, in project `textile-515510`, region `us-east1`. Postgres runs in the cluster exactly as on staging, which runs on olympus from [`argocd/textile/`](../../argocd/textile/README.md); this configuration adds only the bucket it backs up to. Nothing here takes inbound traffic. The dispatch Worker on Cloudflare will reach bot hosts through Cloudflare Tunnel.

| Resource                                                                                 | What it is                                                                                                                                                                     |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| VPC `textile`, subnet `textile-us-east1`                                                 | Nodes `10.0.0.0/20`, pods `10.4.0.0/16`, services `10.8.0.0/20`. No ingress firewall rules.                                                                                    |
| Cloud Router and Cloud NAT `textile`                                                     | Egress for private nodes and pods, with dynamic port allocation so many Gateway sockets to the same Discord address fit on one node.                                           |
| GKE Autopilot cluster `textile`                                                          | Regional, regular channel, private nodes, Workload Identity. People and ArgoCD reach the control plane on its IAM-authorized DNS endpoint.                                     |
| Bucket `textile-515510-db-backups`                                                       | Where CNPG's Barman Cloud plugin archives WAL and writes base backups. Private, uniform access; Barman applies the retention policy.                                           |
| Service account `textile-db`                                                             | CNPG Cluster `textile-db` acts as it through Kubernetes service account `textile/textile-db`, which CNPG creates. It can manage objects in the backup bucket and nothing else. |
| Secrets `textile-token-vault-key`, `textile-bot-host-secret`, `textile-allowed-user-ids` | Secret Manager, replicated in `us-east1` only. They start empty. `DATABASE_URL` comes from CNPG's own `textile-db-app` Secret, as on staging.                                  |
| Service account `textile-bot-host`                                                       | Bot-host pods act as it through Kubernetes service account `textile/textile-bot-host`. It can read the three secrets.                                                          |

OpenTofu refuses to destroy the cluster or the backup bucket.

## First apply

Run these from a machine where `gcloud` is signed in as a project owner. Each step runs once.

1. Create the state bucket, with versioning on so every state stays recoverable:

   ```sh
   gcloud storage buckets create gs://textile-515510-tofu-state \
     --project=textile-515510 --location=us-east1 \
     --uniform-bucket-level-access --public-access-prevention \
     && gcloud storage buckets update gs://textile-515510-tofu-state --versioning
   ```

   `buckets create` has no versioning flag, so the `update` turns it on.

2. Give OpenTofu credentials. The provider reads Application Default Credentials and nothing else:

   ```sh
   gcloud auth application-default login
   gcloud auth application-default set-quota-project textile-515510
   ```

3. Initialize, then read the plan:

   ```sh
   cd terraform/textile-gcp
   tofu init
   tofu plan -out=textile.tfplan
   ```

   Expect 25 to add, 0 to change, 0 to destroy.

4. Apply it:

   ```sh
   tofu apply textile.tfplan
   ```

   The cluster takes 10 to 15 minutes. If the apply fails right after the APIs turn on, wait a minute and run `tofu apply` again: newly enabled APIs take a moment to answer.

5. Put each secret's value. Keep the vault key's copies safe first, because they are the only way to read a restored database:

   ```sh
   # TOKEN_VAULT_KEY: a new key, not staging's. Save it in iCloud Keychain as
   # "Textile production TOKEN_VAULT_KEY" and offline before you add it.
   openssl rand -base64 32 | tr -d '\n' | gcloud secrets versions add textile-token-vault-key --data-file=-

   # BOT_HOST_SECRET: central's dispatch Worker needs the same value, so keep it
   # until the Cloudflare change asks for it.
   openssl rand -base64 32 | tr -d '\n' | gcloud secrets versions add textile-bot-host-secret --data-file=-

   # DISCORD_OAUTH_ALLOWED_USER_IDS: comma-separated Discord user IDs.
   printf %s '<id>,<id>' | gcloud secrets versions add textile-allowed-user-ids --data-file=-
   ```

6. Check that you can reach the cluster:

   ```sh
   gcloud container clusters get-credentials textile --location=us-east1 --dns-endpoint
   kubectl get namespaces
   ```

## Monthly cost

At launch size, on 730 hours a month: two bot-host pods of 0.25 vCPU and 512 MiB, and two CNPG instances of 0.25 vCPU and 1 GiB with a 10 GiB volume each, as staging runs two.

| Item                        | Calculation                                        | Monthly       | Source                                                                                                      |
| --------------------------- | -------------------------------------------------- | ------------- | ----------------------------------------------------------------------------------------------------------- |
| Autopilot pod CPU           | 2 × 0.25 vCPU × $0.0445/h                          | $16.24        | [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)                                           |
| Autopilot pod memory        | 2 × 0.5 GiB × $0.0049225/h                         | $3.59         | [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)                                           |
| Autopilot ephemeral storage | 2 × 1 GiB × $0.0001389/h                           | $0.20         | GKE pricing; the 1 GiB per pod is unverified                                                                |
| Cluster management fee      | $0.10/h = $73.00, less the $74.40 free-tier credit | $0.00         | [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)                                           |
| CNPG instance CPU           | 2 × 0.25 vCPU × $0.0445/h                          | $16.24        | [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)                                           |
| CNPG instance memory        | 2 × 1 GiB × $0.0049225/h                           | $7.19         | [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)                                           |
| CNPG volumes                | 2 × 10 GiB balanced persistent disk                | about $2      | unverified                                                                                                  |
| CNPG operator and plugin    | two small pods                                     | about $5      | unverified; depends on the requests the manifests set                                                       |
| Backup bucket               | a few GiB of WAL and base backups                  | < $0.25       | unverified                                                                                                  |
| Cloud NAT gateway           | 2 nodes × $0.0014/h                                | $2.04         | [Cloud NAT pricing](https://cloud.google.com/nat/pricing); node count unverified                            |
| Cloud NAT address           | 1 IP × $0.005/h                                    | $3.65         | [Cloud NAT pricing](https://cloud.google.com/nat/pricing)                                                   |
| Cloud NAT data processing   | about 10 GiB × $0.045                              | $0.45         | Cloud NAT pricing; the traffic is unverified                                                                |
| Internet egress             | Gateway, REST and voice traffic out                | unverified    | [Network pricing](https://cloud.google.com/vpc/network-pricing)                                             |
| Secret Manager              | 3 active versions, under 10,000 reads              | $0.00         | [Secret Manager pricing](https://cloud.google.com/secret-manager/pricing): 6 versions and 10,000 reads free |
| State bucket                | a few KB                                           | < $0.01       | unverified                                                                                                  |
| **Total**                   |                                                    | **about $57** | plus egress                                                                                                 |

The GKE rates are the ones the pricing page shows by default, for Iowa (`us-central1`). It renders other regions with JavaScript, so the `us-east1` rates are unverified. The free-tier credit covers one Autopilot or zonal cluster per billing account, so a second cluster on the same account pays the full $73.00. Running one CNPG instance in place of two saves about $12 a month, at the cost of failover.

## Next steps

These are separate changes:

1. Kubernetes manifests for production: the bot hosts' StatefulSet, headless Service, NetworkPolicy, and service account `textile/textile-bot-host` annotated with `iam.gke.io/gcp-service-account: textile-bot-host@textile-515510.iam.gserviceaccount.com`; and CNPG Cluster `textile-db` with a Barman Cloud `ObjectStore` on `gs://textile-515510-db-backups`, its service account annotated with output `db_google_service_account`, as `argocd/textile/postgresql.yaml` does on staging.
2. ArgoCD wiring: either olympus's ArgoCD deploys to this cluster through the DNS endpoint, or the cluster runs its own ArgoCD.
3. Cloudflare Tunnel from the cluster to the dispatch Worker, with `cloudflared` as a Deployment.
4. Secret sync from Secret Manager into the cluster, for example with GKE's Secret Manager add-on or External Secrets.
