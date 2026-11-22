# Textile on Google Cloud

The Google Cloud half of Textile production: bot hosts on GKE Autopilot and their Postgres on Cloud SQL, in project `textile-515510`, region `us-east1`. Staging runs on olympus from [`argocd/textile/`](../../argocd/textile/README.md). Nothing here takes inbound traffic. The dispatch Worker on Cloudflare will reach bot hosts through Cloudflare Tunnel.

| Resource                                                                                                        | What it is                                                                                                                                                                                                                             |
| --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| VPC `textile`, subnet `textile-us-east1`                                                                        | Nodes `10.0.0.0/20`, pods `10.4.0.0/16`, services `10.8.0.0/20`. No ingress firewall rules.                                                                                                                                            |
| Cloud Router and Cloud NAT `textile`                                                                            | Egress for private nodes and pods, with dynamic port allocation so many Gateway sockets to the same Discord address fit on one node.                                                                                                   |
| GKE Autopilot cluster `textile`                                                                                 | Regional, regular channel, private nodes, Workload Identity. People and ArgoCD reach the control plane on its IAM-authorized DNS endpoint.                                                                                             |
| Cloud SQL instance `textile`                                                                                    | PostgreSQL 18, Enterprise, `db-custom-1-3840` (1 vCPU, 3.75 GB), zonal, private IP only through private service access on `10.16.0.0/20`. Daily backups kept 14 days, 7 days of point-in-time recovery, maintenance Sundays 04:00 UTC. |
| Database and user `textile`                                                                                     | The bot hosts' `DATABASE_URL`. OpenTofu generates the password and writes it only to Secret Manager and the user; it never reaches state.                                                                                              |
| Secrets `textile-token-vault-key`, `textile-bot-host-secret`, `textile-allowed-user-ids`, `textile-db-password` | Secret Manager, replicated in `us-east1` only. All but the database password start empty.                                                                                                                                              |
| Service account `textile-bot-host`                                                                              | Bot-host pods act as it through Kubernetes service account `textile/textile-bot-host`. It holds Cloud SQL Client and read access to the four secrets.                                                                                  |

OpenTofu refuses to destroy the cluster or the database, and Cloud SQL's own deletion protection guards the database against deletion from the console too.

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

   Expect 31 to add, 0 to change, 0 to destroy.

4. Apply it:

   ```sh
   tofu apply textile.tfplan
   ```

   The cluster and the database take 10 to 15 minutes each. If the apply fails right after the APIs turn on, wait a minute and run `tofu apply` again: newly enabled APIs take a moment to answer.

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

   `textile-db-password` already has its value. To rotate it, bump `db_password_version` in `main.tf` and apply.

6. Check that you can reach the cluster and the database exists:

   ```sh
   gcloud container clusters get-credentials textile --location=us-east1 --dns-endpoint
   kubectl get namespaces
   gcloud sql instances describe textile --format='value(state,ipAddresses[0].ipAddress)'   # RUNNABLE, 10.16.x.x
   ```

## Monthly cost

At launch size: two bot-host pods of 0.25 vCPU and 512 MiB each, on 730 hours a month.

| Item                        | Calculation                                        | Monthly    | Source                                                                                                      |
| --------------------------- | -------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------- |
| Autopilot pod CPU           | 2 × 0.25 vCPU × $0.0445/h                          | $16.24     | [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)                                           |
| Autopilot pod memory        | 2 × 0.5 GiB × $0.0049225/h                         | $3.59      | [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)                                           |
| Autopilot ephemeral storage | 2 × 1 GiB × $0.0001389/h                           | $0.20      | GKE pricing; the 1 GiB per pod is unverified                                                                |
| Cluster management fee      | $0.10/h = $73.00, less the $74.40 free-tier credit | $0.00      | [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)                                           |
| Cloud SQL CPU               | 1 vCPU × $0.0413/h                                 | $30.15     | [Cloud SQL pricing](https://cloud.google.com/sql/pricing)                                                   |
| Cloud SQL memory            | 3.75 GiB × $0.007/h                                | $19.16     | [Cloud SQL pricing](https://cloud.google.com/sql/pricing)                                                   |
| Cloud SQL SSD               | 10 GiB × $0.000232877/h                            | $1.70      | [Cloud SQL pricing](https://cloud.google.com/sql/pricing)                                                   |
| Cloud SQL backups and logs  | about 2 GiB × $0.000109589/h                       | $0.16      | Cloud SQL pricing; the 2 GiB is unverified                                                                  |
| Cloud NAT gateway           | 2 nodes × $0.0014/h                                | $2.04      | [Cloud NAT pricing](https://cloud.google.com/nat/pricing); node count unverified                            |
| Cloud NAT address           | 1 IP × $0.005/h                                    | $3.65      | [Cloud NAT pricing](https://cloud.google.com/nat/pricing)                                                   |
| Cloud NAT data processing   | about 10 GiB × $0.045                              | $0.45      | Cloud NAT pricing; the traffic is unverified                                                                |
| Internet egress             | Gateway, REST and voice traffic out                | unverified | [Network pricing](https://cloud.google.com/vpc/network-pricing)                                             |
| Secret Manager              | 4 active versions, under 10,000 reads              | $0.00      | [Secret Manager pricing](https://cloud.google.com/secret-manager/pricing): 6 versions and 10,000 reads free |
| State bucket                | a few KB                                           | < $0.01    | unverified                                                                                                  |
| **Total**                   |                                                    | **$77.34** | plus egress                                                                                                 |

The GKE and Cloud SQL rates are the ones the pricing pages show by default, for Iowa (`us-central1`). They render other regions with JavaScript, so the `us-east1` rates are unverified. The free-tier credit covers one Autopilot or zonal cluster per billing account, so a second cluster on the same account pays the full $73.00. Cloud SQL is two-thirds of the bill: high availability would roughly double its $51.17, and a shared-core `db-g1-small` would cost $25.55 but has no SLA.

## Next steps

These are separate changes:

1. Kubernetes manifests for production bot hosts: StatefulSet, headless Service, NetworkPolicy, and service account `textile/textile-bot-host` annotated with `iam.gke.io/gcp-service-account: textile-bot-host@textile-515510.iam.gserviceaccount.com`. Connect to Cloud SQL through the Auth Proxy sidecar, using output `sql_connection_name`, and count its requests in the pod cost.
2. ArgoCD wiring: either olympus's ArgoCD deploys to this cluster through the DNS endpoint, or the cluster runs its own ArgoCD.
3. Cloudflare Tunnel from the cluster to the dispatch Worker, with `cloudflared` as a Deployment.
4. Secret sync from Secret Manager into the cluster, for example with GKE's Secret Manager add-on or External Secrets.
