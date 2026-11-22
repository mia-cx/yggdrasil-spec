# Textile production bot hosts on Google Cloud: a private GKE Autopilot
# cluster in us-east1, next to Discord, and the bucket its CloudNativePG
# database backs up to. Postgres runs in the cluster under CNPG, as staging
# does on olympus. Nothing here takes inbound traffic: the dispatch Worker
# reaches bot hosts through Cloudflare Tunnel, which a later change adds. The
# provider authenticates via Application Default Credentials only (README
# step 2).

locals {
  project = "textile-515510"
  region  = "us-east1"

  # The Kubernetes service account bot-host pods run as.
  bot_host_namespace       = "textile"
  bot_host_service_account = "textile-bot-host"

  # CNPG runs each instance of Cluster `textile-db` as a Kubernetes service
  # account of the same name, which the Barman Cloud plugin uses for backups.
  db_service_account = "textile-db"

  # Secrets bot hosts read, as Secret Manager IDs. Each maps to the env var
  # staging's bot hosts take from a Kubernetes Secret (argocd/textile/).
  # DATABASE_URL comes from CNPG's own `textile-db-app` Secret, as on staging.
  bot_host_secrets = {
    "textile-token-vault-key"  = "TOKEN_VAULT_KEY"
    "textile-bot-host-secret"  = "BOT_HOST_SECRET"
    "textile-allowed-user-ids" = "DISCORD_OAUTH_ALLOWED_USER_IDS"
  }
}

provider "google" {
  project = local.project
  region  = local.region
}

resource "google_project_service" "apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com", # Project IAM bindings.
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com", # Workload Identity token exchange.
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ])

  service = each.value

  # Turning an API off would break whatever else in the project uses it.
  disable_on_destroy = false
}

# --- Network ----------------------------------------------------------------

resource "google_compute_network" "textile" {
  name                    = "textile"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.apis]
}

# A custom VPC has no ingress allow rules, so nothing reaches the nodes from
# outside; GKE adds only the rules its own control plane needs.
resource "google_compute_subnetwork" "textile" {
  name          = "textile-us-east1"
  region        = local.region
  network       = google_compute_network.textile.id
  ip_cidr_range = "10.0.0.0/20" # Nodes.

  # Private nodes reach Google APIs without NAT.
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }
}

resource "google_compute_router" "textile" {
  name    = "textile"
  region  = local.region
  network = google_compute_network.textile.id
}

# Egress for private nodes and pods: Gateway WebSockets, REST, voice UDP and
# npm installs.
resource "google_compute_router_nat" "textile" {
  name                               = "textile"
  router                             = google_compute_router.textile.name
  region                             = local.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Every Gateway shard holds a socket to the same few Discord addresses, and
  # a static allocation caps a node at 64 connections per destination.
  # Dynamic allocation grows a busy node's share instead.
  enable_dynamic_port_allocation      = true
  enable_endpoint_independent_mapping = false
  min_ports_per_vm                    = 1024
  max_ports_per_vm                    = 65536

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- GKE Autopilot ----------------------------------------------------------

resource "google_container_cluster" "textile" {
  name             = "textile"
  location         = local.region
  enable_autopilot = true

  network    = google_compute_network.textile.id
  subnetwork = google_compute_subnetwork.textile.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = "REGULAR"
  }

  # People and ArgoCD reach the control plane only on its DNS endpoint, where
  # every request carries a Google identity that IAM checks before RBAC does.
  # An IP allowlist would need fixed source addresses, which neither Mia's
  # devices nor olympus have, and anyone at an allowed address could try
  # leaked credentials; IAM access works from anywhere and is revoked per
  # identity. The external IP endpoint is off. The internal one stays for the
  # nodes, since GKE doesn't document how nodes reach a control plane with
  # every IP endpoint disabled.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
  }

  # Autopilot enables Workload Identity (pool textile-515510.svc.id.goog) and
  # Dataplane V2, which enforces NetworkPolicy.

  deletion_protection = true
}

# --- Database backups --------------------------------------------------------

# CNPG's Barman Cloud plugin archives WAL continuously and writes base
# backups here, as staging does to RustFS. Barman applies the retention
# policy itself, so the bucket keeps no lifecycle rules of its own.
resource "google_storage_bucket" "db_backups" {
  name                        = "${local.project}-db-backups"
  location                    = local.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Backups are the last copy of every stored bot token: never destroy them
  # from here.
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.apis]
}

resource "google_service_account" "db" {
  account_id   = "textile-db"
  display_name = "Textile database backups"

  depends_on = [google_project_service.apis]
}

# The database pods act as this account through Workload Identity.
resource "google_service_account_iam_member" "db_workload_identity" {
  service_account_id = google_service_account.db.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.project}.svc.id.goog[${local.bot_host_namespace}/${local.db_service_account}]"

  depends_on = [google_container_cluster.textile]
}

# Barman writes, lists, reads back and prunes its own objects.
resource "google_storage_bucket_iam_member" "db_backups" {
  bucket = google_storage_bucket.db_backups.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.db.member
}

# --- Secrets and identity -----------------------------------------------------

# Empty containers. Mia adds each value (README step 5).
resource "google_secret_manager_secret" "bot_host" {
  for_each  = local.bot_host_secrets
  secret_id = each.key

  labels = {
    app = "textile-bot-host"
  }

  replication {
    user_managed {
      replicas {
        location = local.region
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_service_account" "bot_host" {
  account_id   = "textile-bot-host"
  display_name = "Textile bot hosts"

  depends_on = [google_project_service.apis]
}

# Bot-host pods act as this account through Workload Identity. The pool
# exists once the cluster does.
resource "google_service_account_iam_member" "bot_host_workload_identity" {
  service_account_id = google_service_account.bot_host.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.project}.svc.id.goog[${local.bot_host_namespace}/${local.bot_host_service_account}]"

  depends_on = [google_container_cluster.textile]
}

resource "google_secret_manager_secret_iam_member" "bot_host" {
  for_each  = google_secret_manager_secret.bot_host
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.bot_host.member
}
