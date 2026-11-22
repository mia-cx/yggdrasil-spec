# Textile production bot hosts on Google Cloud: a private GKE Autopilot
# cluster and Cloud SQL for Postgres in us-east1, next to Discord. Nothing
# here takes inbound traffic: the dispatch Worker reaches bot hosts through
# Cloudflare Tunnel, which a later change adds. The provider authenticates
# via Application Default Credentials only (README step 2).

locals {
  project = "textile-515510"
  region  = "us-east1"

  # The Kubernetes service account bot-host pods run as.
  bot_host_namespace       = "textile"
  bot_host_service_account = "textile-bot-host"

  # Bump to rotate the database password: the next apply writes a new secret
  # version and sets the same value on the database user.
  db_password_version = 1

  # Secrets bot hosts read, as Secret Manager IDs. Each maps to the env var
  # staging's bot hosts take from a Kubernetes Secret (argocd/textile/).
  bot_host_secrets = {
    "textile-token-vault-key"  = "TOKEN_VAULT_KEY"
    "textile-bot-host-secret"  = "BOT_HOST_SECRET"
    "textile-allowed-user-ids" = "DISCORD_OAUTH_ALLOWED_USER_IDS"
    "textile-db-password"      = "DATABASE_URL" # Its password; the URL adds host, user and database.
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
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
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

# --- Cloud SQL ---------------------------------------------------------------

# Private service access: Cloud SQL gets addresses from this range, peered
# into the VPC.
resource "google_compute_global_address" "sql" {
  name          = "textile-sql"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = "10.16.0.0"
  prefix_length = 20
  network       = google_compute_network.textile.id
}

resource "google_service_networking_connection" "sql" {
  network                 = google_compute_network.textile.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.sql.name]

  # Removing the peering fails while Cloud SQL still uses it; the instance's
  # deletion protection makes that the normal case.
  deletion_policy = "ABANDON"
}

resource "google_sql_database_instance" "textile" {
  name                = "textile"
  region              = local.region
  database_version    = "POSTGRES_18" # Staging runs 18 (argocd/textile/postgresql.yaml).
  deletion_protection = true

  settings {
    # Enterprise Plus is the default edition for new Postgres 16+ instances.
    edition = "ENTERPRISE"
    # The smallest dedicated-core tier, 1 vCPU and 3.75 GB, covered by the
    # SLA. Shared-core tiers are not.
    tier                        = "db-custom-1-3840"
    availability_type           = "ZONAL"
    disk_type                   = "PD_SSD"
    disk_size                   = 10
    disk_autoresize             = true
    deletion_protection_enabled = true

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.textile.id
      # Admits the Cloud SQL Auth Proxy and direct TLS clients.
      ssl_mode = "ENCRYPTED_ONLY"
    }

    # Times are UTC. Enterprise keeps at most 7 days of logs for
    # point-in-time recovery; staging's window is 14.
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = 14
      }
    }

    maintenance_window {
      day          = 7 # Sunday.
      hour         = 4
      update_track = "stable"
    }
  }

  depends_on = [google_service_networking_connection.sql]
}

resource "google_sql_database" "textile" {
  name     = "textile"
  instance = google_sql_database_instance.textile.name
}

# Generated per run and never stored: write-only arguments send it to Secret
# Manager and the database user, and only the version number reaches state.
ephemeral "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_user" "textile" {
  name                = "textile"
  instance            = google_sql_database_instance.textile.name
  password_wo         = ephemeral.random_password.db.result
  password_wo_version = local.db_password_version
}

resource "google_secret_manager_secret_version" "db_password" {
  secret                 = google_secret_manager_secret.bot_host["textile-db-password"].id
  secret_data_wo         = ephemeral.random_password.db.result
  secret_data_wo_version = local.db_password_version
}

# --- Secrets and identity -----------------------------------------------------

# Empty containers, except the database password above. Mia adds each other
# value (README step 5).
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

# Cloud SQL grants connect per project; this project holds one instance.
resource "google_project_iam_member" "bot_host_sql_client" {
  project = local.project
  role    = "roles/cloudsql.client"
  member  = google_service_account.bot_host.member
}

resource "google_secret_manager_secret_iam_member" "bot_host" {
  for_each  = google_secret_manager_secret.bot_host
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.bot_host.member
}
