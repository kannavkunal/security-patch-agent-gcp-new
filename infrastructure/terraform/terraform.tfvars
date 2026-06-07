# Project Configuration
project_id = "YOUR_PROJECT_ID"  # Replace with your actual GCP project ID
region     = "us-central1"

# Use existing resources instead of creating new ones
use_existing_cluster          = true
use_existing_registry         = true
use_existing_service_account  = true

# Cluster and resource names (must match existing resources)
cluster_name           = "code-vulnerability-scanner"
artifact_registry_repo = "security-patch-agent"
namespace              = "security-patch-agent"
k8s_service_account    = "security-patch-agent"

# Alert configuration
alert_email = "kunal@example.com"  # Replace with your email

# Components to deploy (skip GKE/registry creation, only deploy supporting resources)
components = "all"
