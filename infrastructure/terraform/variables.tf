variable "project_id" {
  description = "GCP Project ID"
  type        = string
  description = "GCP Project ID - must be provided"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "code-vulnerability-scanner"
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "security-patch-agent"
}

variable "k8s_service_account" {
  description = "Kubernetes service account name"
  type        = string
  default     = "security-patch-agent-sa"
}

variable "artifact_registry_repo" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "security-patch-agent"
}

variable "components" {
  description = "Components to deploy (all, gke-only, artifact-registry-only, monitoring-only)"
  type        = string
  default     = "all"
}

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = "kunal@example.com"
}

variable "whitelisted_ips" {
  description = "List of whitelisted IP addresses for API access"
  type        = list(string)
  default     = ["199.167.52.5/32"]
}

variable "use_existing_cluster" {
  description = "Use existing GKE cluster instead of creating new one"
  type        = bool
  default     = false
}

variable "use_existing_registry" {
  description = "Use existing Artifact Registry instead of creating new one"
  type        = bool
  default     = false
}

variable "use_existing_service_account" {
  description = "Use existing service account instead of creating new one"
  type        = bool
  default     = false
}
