output "cluster_name" {
  description = "GKE Autopilot cluster name"
  value       = google_container_cluster.textile.name
}

output "cluster_location" {
  description = "GKE cluster region"
  value       = google_container_cluster.textile.location
}

output "cluster_dns_endpoint" {
  description = "The control plane's IAM-authorized DNS endpoint"
  value       = google_container_cluster.textile.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint
}

output "bot_host_google_service_account" {
  description = "Email the bot hosts' Kubernetes service account annotates as iam.gke.io/gcp-service-account"
  value       = google_service_account.bot_host.email
}

output "bot_host_kubernetes_service_account" {
  description = "Namespace and name the Workload Identity binding trusts"
  value       = "${local.bot_host_namespace}/${local.bot_host_service_account}"
}

output "secret_ids" {
  description = "Secret Manager secret IDs, keyed by the bot-host env var each feeds"
  value       = { for id, env in local.bot_host_secrets : env => google_secret_manager_secret.bot_host[id].secret_id }
}
