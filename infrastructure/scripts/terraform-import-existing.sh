#!/bin/bash
set -e

PROJECT_ID="${GCP_PROJECT_ID}"
REGION="${GCP_LOCATION:-us-central1}"

if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: GCP_PROJECT_ID environment variable is not set"
    exit 1
fi

echo "================================================"
echo "Importing Existing Resources into Terraform State"
echo "================================================"
echo ""
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""

cd infrastructure/terraform

# Initialize Terraform
terraform init

echo "Importing existing resources..."
echo ""

# Import VPC if exists
echo "1. VPC Network..."
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_compute_network.vpc[0]' \
  "projects/$PROJECT_ID/global/networks/code-vulnerability-scanner-vpc" 2>/dev/null || \
  echo "  ⏭️  VPC not found or already in state"

# Import Service Account if exists
echo "2. Service Account..."
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_service_account.app_sa[0]' \
  "projects/$PROJECT_ID/serviceAccounts/security-patch-agent@$PROJECT_ID.iam.gserviceaccount.com" 2>/dev/null || \
  echo "  ⏭️  Service account not found or already in state"

# Import Logging Metrics if they exist
echo "3. Logging Metrics..."
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_logging_metric.scan_completed' \
  "$PROJECT_ID/security_patch_agent_scans_completed" 2>/dev/null || \
  echo "  ⏭️  Metric not found or already in state"

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_logging_metric.scan_failed' \
  "$PROJECT_ID/security_patch_agent_scans_failed" 2>/dev/null || \
  echo "  ⏭️  Metric not found or already in state"

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_logging_metric.pr_created' \
  "$PROJECT_ID/security_patch_agent_prs_created" 2>/dev/null || \
  echo "  ⏭️  Metric not found or already in state"

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_logging_metric.evidence_generated' \
  "$PROJECT_ID/security_patch_agent_evidence_generated" 2>/dev/null || \
  echo "  ⏭️  Metric not found or already in state"

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_logging_metric.api_requests' \
  "$PROJECT_ID/security_patch_agent_api_requests" 2>/dev/null || \
  echo "  ⏭️  Metric not found or already in state"

# Import Pub/Sub Topics if they exist
echo "4. Pub/Sub Topics..."
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_pubsub_topic.dead_letter' \
  "projects/$PROJECT_ID/topics/security-scan-events-dlq" 2>/dev/null || \
  echo "  ⏭️  Topic not found or already in state"

echo ""
echo "================================================"
echo "Import Complete!"
echo "================================================"
echo ""
echo "Now run: terraform apply"
