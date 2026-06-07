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
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_compute_network.vpc[0]' \
  "projects/$PROJECT_ID/global/networks/code-vulnerability-scanner-vpc" 2>/dev/null || \
  echo "  ⏭️  VPC not found or already in state"

# Import Service Account if exists
echo "2. Service Account..."
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_service_account.app_sa[0]' \
  "projects/$PROJECT_ID/serviceAccounts/security-patch-agent@$PROJECT_ID.iam.gserviceaccount.com" 2>/dev/null || \
  echo "  ⏭️  Service account not found or already in state"

# Import GCS Bucket if exists
echo "3. GCS Bucket..."
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_storage_bucket.evidence_bucket' \
  "security-patch-evidence-$PROJECT_ID" 2>/dev/null || \
  echo "  ⏭️  Bucket not found or already in state"

# Import Artifact Registry if exists
echo "4. Artifact Registry..."
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_artifact_registry_repository.docker_repo[0]' \
  "projects/$PROJECT_ID/locations/$REGION/repositories/security-patch-agent" 2>/dev/null || \
  echo "  ⏭️  Repository not found or already in state"

# Import Logging Metrics if they exist
echo "5. Logging Metrics..."
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_logging_metric.scan_completed' \
  "$PROJECT_ID/security_patch_agent_scans_completed" 2>/dev/null || \
  echo "  ⏭️  scan_completed not found or already in state"

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_logging_metric.scan_failed' \
  "$PROJECT_ID/security_patch_agent_scans_failed" 2>/dev/null || \
  echo "  ⏭️  scan_failed not found or already in state"

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_logging_metric.pr_created' \
  "$PROJECT_ID/security_patch_agent_prs_created" 2>/dev/null || \
  echo "  ⏭️  pr_created not found or already in state"

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_logging_metric.evidence_generated' \
  "$PROJECT_ID/security_patch_agent_evidence_generated" 2>/dev/null || \
  echo "  ⏭️  evidence_generated not found or already in state"

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_logging_metric.api_requests' \
  "$PROJECT_ID/security_patch_agent_api_requests" 2>/dev/null || \
  echo "  ⏭️  api_requests not found or already in state"

# Import Pub/Sub Topics if they exist
echo "6. Pub/Sub Topics..."
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_pubsub_topic.security_scan_events' \
  "projects/$PROJECT_ID/topics/security-scan-events" 2>/dev/null || \
  echo "  ⏭️  security-scan-events not found or already in state"

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_pubsub_topic.dead_letter' \
  "projects/$PROJECT_ID/topics/security-scan-events-dlq" 2>/dev/null || \
  echo "  ⏭️  dead_letter not found or already in state"

# Import Pub/Sub Subscription if exists
echo "7. Pub/Sub Subscription..."
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=all" \
  'google_pubsub_subscription.dead_letter_sub' \
  "projects/$PROJECT_ID/subscriptions/scan-events-dlq-subscription" 2>/dev/null || \
  echo "  ⏭️  Subscription not found or already in state"

echo ""
echo "================================================"
echo "Import Complete!"
echo "================================================"
echo ""
echo "Now run: terraform apply"
