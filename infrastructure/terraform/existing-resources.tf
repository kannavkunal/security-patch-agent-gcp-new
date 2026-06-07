# Data sources for existing infrastructure
# Use these if GKE cluster and Artifact Registry already exist

# Existing GKE cluster
data "google_container_cluster" "existing" {
  count    = var.use_existing_cluster ? 1 : 0
  name     = var.cluster_name
  location = var.region
}

# Existing Artifact Registry
data "google_artifact_registry_repository" "existing" {
  count         = var.use_existing_registry ? 1 : 0
  location      = var.region
  repository_id = var.artifact_registry_repo
}

# Existing service account (if it exists)
data "google_service_account" "existing" {
  count      = var.use_existing_service_account ? 1 : 0
  account_id = "security-patch-agent"
}
