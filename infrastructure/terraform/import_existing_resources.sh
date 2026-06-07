#!/bin/bash
# Import existing GCP resources into Terraform state
# Run this from the terraform directory: ./import_existing_resources.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔄 Importing Existing GCP Resources into Terraform State${NC}"
echo "================================================================"
echo ""

# Read project ID from terraform.tfvars or prompt user
if [ -f "terraform.tfvars" ]; then
    PROJECT_ID=$(grep 'project_id' terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
else
    echo -e "${YELLOW}Please enter your GCP Project ID:${NC}"
    read PROJECT_ID
fi

REGION="us-central1"

echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Function to import resource with error handling
import_resource() {
    local resource_type=$1
    local resource_name=$2
    local resource_id=$3

    echo -e "${YELLOW}Importing: ${resource_name}${NC}"

    if terraform import "$resource_type.$resource_name" "$resource_id" 2>&1 | grep -q "already managed"; then
        echo -e "${GREEN}✓ Already imported${NC}"
    elif terraform import "$resource_type.$resource_name" "$resource_id"; then
        echo -e "${GREEN}✓ Successfully imported${NC}"
    else
        echo -e "${RED}✗ Failed to import (may not exist)${NC}"
    fi
    echo ""
}

echo "Starting imports..."
echo ""

# 1. Storage Bucket (GCS)
import_resource "google_storage_bucket" "evidence_bucket" \
    "security-patch-evidence-${PROJECT_ID}"

# 2. VPC Network
import_resource "google_compute_network" "vpc[0]" \
    "projects/${PROJECT_ID}/global/networks/code-vulnerability-scanner-vpc"

# 3. Subnet
import_resource "google_compute_subnetwork" "subnet[0]" \
    "projects/${PROJECT_ID}/regions/${REGION}/subnetworks/code-vulnerability-scanner-subnet"

# 4. GKE Cluster (if exists and use_existing_cluster=true)
import_resource "google_container_cluster" "primary[0]" \
    "projects/${PROJECT_ID}/locations/${REGION}/clusters/code-vulnerability-scanner"

# 5. Artifact Registry
import_resource "google_artifact_registry_repository" "docker_repo[0]" \
    "projects/${PROJECT_ID}/locations/${REGION}/repositories/security-patch-agent"

# 6. Service Account
import_resource "google_service_account" "app_sa[0]" \
    "projects/${PROJECT_ID}/serviceAccounts/security-patch-agent@${PROJECT_ID}.iam.gserviceaccount.com"

# 7. Pub/Sub Topic
import_resource "google_pubsub_topic" "security_scan_events" \
    "projects/${PROJECT_ID}/topics/security-scan-events"

# 8. Pub/Sub Dead Letter Topic
import_resource "google_pubsub_topic" "dead_letter" \
    "projects/${PROJECT_ID}/topics/security-scan-events-dlq"

# 9. Pub/Sub Subscription
import_resource "google_pubsub_subscription" "security_scan_events_sub" \
    "projects/${PROJECT_ID}/subscriptions/scan-events-subscription"

# 10. Logging Metrics
import_resource "google_logging_metric" "scan_completed" \
    "projects/${PROJECT_ID}/metrics/security_patch_agent_scans_completed"

import_resource "google_logging_metric" "scan_failed" \
    "projects/${PROJECT_ID}/metrics/security_patch_agent_scans_failed"

import_resource "google_logging_metric" "pr_created" \
    "projects/${PROJECT_ID}/metrics/security_patch_agent_prs_created"

import_resource "google_logging_metric" "evidence_generated" \
    "projects/${PROJECT_ID}/metrics/security_patch_agent_evidence_generated"

import_resource "google_logging_metric" "api_requests" \
    "projects/${PROJECT_ID}/metrics/security_patch_agent_api_requests"

# 11. BigQuery Dataset
import_resource "google_bigquery_dataset" "security_scans" \
    "projects/${PROJECT_ID}/datasets/security_scans"

# 12. BigQuery Tables
import_resource "google_bigquery_table" "scans" \
    "projects/${PROJECT_ID}/datasets/security_scans/tables/scans"

import_resource "google_bigquery_table" "vulnerabilities" \
    "projects/${PROJECT_ID}/datasets/security_scans/tables/vulnerabilities"

import_resource "google_bigquery_table" "patches" \
    "projects/${PROJECT_ID}/datasets/security_scans/tables/patches"

import_resource "google_bigquery_table" "scan_outcomes" \
    "projects/${PROJECT_ID}/datasets/security_scans/tables/scan_outcomes"

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}✅ Import Complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Edit terraform.tfvars and set your project_id"
echo "2. Run: terraform plan (should show no changes if all imports succeeded)"
echo "3. Run: terraform apply (to sync any remaining resources)"
echo ""
