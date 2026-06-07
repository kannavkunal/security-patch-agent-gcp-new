output "cluster_name" {
  description = "GKE cluster name"
  value       = var.components == "all" || var.components == "gke-only" ? google_container_cluster.primary[0].name : null
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = var.components == "all" || var.components == "gke-only" ? google_container_cluster.primary[0].endpoint : null
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = var.components == "all" || var.components == "gke-only" ? google_container_cluster.primary[0].master_auth[0].cluster_ca_certificate : null
  sensitive   = true
}

output "service_account_email" {
  description = "Service account email for Workload Identity"
  value       = var.components == "all" || var.components == "gke-only" ? google_service_account.app_sa[0].email : null
}

output "artifact_registry_url" {
  description = "Artifact Registry repository URL"
  value       = var.components == "all" || var.components == "artifact-registry-only" ? "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo}" : null
}

output "vpc_network_name" {
  description = "VPC network name"
  value       = var.components == "all" || var.components == "gke-only" ? google_compute_network.vpc[0].name : null
}

output "subnet_name" {
  description = "Subnet name"
  value       = var.components == "all" || var.components == "gke-only" ? google_compute_subnetwork.subnet[0].name : null
}

output "notification_channel_id" {
  description = "Monitoring notification channel ID"
  value       = var.components == "all" || var.components == "monitoring-only" ? google_monitoring_notification_channel.email[0].id : null
}
