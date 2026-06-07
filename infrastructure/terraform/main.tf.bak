terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "compact-orb-498606-f9-terraform-state"
    prefix = "security-patch-agent"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudtrace.googleapis.com",
    "aiplatform.googleapis.com",
    "servicenetworking.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# GKE Autopilot Cluster
resource "google_container_cluster" "primary" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  name     = var.cluster_name
  location = var.region

  enable_autopilot = true

  # Network configuration
  network    = google_compute_network.vpc[0].name
  subnetwork = google_compute_subnetwork.subnet[0].name

  # IP allocation policy
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Release channel
  release_channel {
    channel = "REGULAR"
  }

  depends_on = [google_project_service.required_apis]
}

# VPC Network
resource "google_compute_network" "vpc" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc[0].id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }

  private_ip_google_access = true
}

# Artifact Registry
resource "google_artifact_registry_repository" "docker_repo" {
  count = var.components == "all" || var.components == "artifact-registry-only" ? 1 : 0

  location      = var.region
  repository_id = var.artifact_registry_repo
  description   = "Docker repository for security patch agent"
  format        = "DOCKER"

  # Note: Cleanup policies can be added later via GCP Console if needed
  # Removed during initial setup to avoid API compatibility issues

  depends_on = [google_project_service.required_apis]
}

# Service Account for Workload Identity
resource "google_service_account" "app_sa" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  account_id   = "security-patch-agent"
  display_name = "Security Patch Agent Service Account"
  description  = "Service account for security patch agent with Workload Identity"
}

# IAM bindings for service account
resource "google_project_iam_member" "app_sa_ai_user" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.app_sa[0].email}"
}

resource "google_project_iam_member" "app_sa_logging_writer" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.app_sa[0].email}"
}

resource "google_project_iam_member" "app_sa_monitoring_writer" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.app_sa[0].email}"
}

resource "google_project_iam_member" "app_sa_trace_writer" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.app_sa[0].email}"
}

# Workload Identity binding
resource "google_service_account_iam_member" "workload_identity_binding" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  service_account_id = google_service_account.app_sa[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.k8s_service_account}]"
}

# Cloud Monitoring Notification Channel
resource "google_monitoring_notification_channel" "email" {
  count = var.components == "all" || var.components == "monitoring-only" ? 1 : 0

  display_name = "Security Patch Agent Alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }

  enabled = true
}

# Alert Policy - High Error Rate
# NOTE: Commented out for initial deployment - custom metrics need to be created first
# Uncomment after application is deployed and generating metrics
# resource "google_monitoring_alert_policy" "high_error_rate" {
#   count = var.components == "all" || var.components == "monitoring-only" ? 1 : 0
#
#   display_name = "Security Patch Agent - High Error Rate"
#   combiner     = "OR"
#
#   conditions {
#     display_name = "Error rate > 5%"
#
#     condition_threshold {
#       filter          = "resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"${var.namespace}\" AND metric.type=\"logging.googleapis.com/user/error_count\""
#       duration        = "300s"
#       comparison      = "COMPARISON_GT"
#       threshold_value = 5
#
#       aggregations {
#         alignment_period   = "60s"
#         per_series_aligner = "ALIGN_RATE"
#       }
#     }
#   }
#
#   notification_channels = [google_monitoring_notification_channel.email[0].id]
#
#   alert_strategy {
#     auto_close = "1800s"
#   }
# }

# Alert Policy - Pod Restart
# NOTE: Commented out for initial deployment - pods need to exist first
# Uncomment after application is deployed
# resource "google_monitoring_alert_policy" "pod_restart" {
#   count = var.components == "all" || var.components == "monitoring-only" ? 1 : 0
#
#   display_name = "Security Patch Agent - Pod Restarts"
#   combiner     = "OR"
#
#   conditions {
#     display_name = "Pod restarted"
#
#     condition_threshold {
#       filter          = "resource.type=\"k8s_pod\" AND resource.labels.namespace_name=\"${var.namespace}\" AND metric.type=\"kubernetes.io/container/restart_count\""
#       duration        = "60s"
#       comparison      = "COMPARISON_GT"
#       threshold_value = 0
#
#       aggregations {
#         alignment_period   = "60s"
#         per_series_aligner = "ALIGN_DELTA"
#       }
#     }
#   }
#
#   notification_channels = [google_monitoring_notification_channel.email[0].id]
# }

# GCS Bucket for Terraform state (pre-created, imported)
# Create this manually: gsutil mb -p compact-orb-498606-f9 -l us-central1 gs://compact-orb-498606-f9-terraform-state
