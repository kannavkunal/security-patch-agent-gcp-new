#!/bin/bash
# Fix corrupted Terraform state by importing all existing resources
# Run from terraform directory: ./fix_state.sh

set +e  # Don't exit on errors

PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

echo "🔧 Fixing Terraform State"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Initialize terraform
terraform init

echo "📥 Importing all existing resources..."
echo ""

# Import each resource (suppress errors if already in state)
terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_logging_metric.scan_completed' \
  "projects/$PROJECT_ID/metrics/security_patch_agent_scans_completed" 2>&1 | grep -v "Error" || true

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_logging_metric.scan_failed' \
  "projects/$PROJECT_ID/metrics/security_patch_agent_scans_failed" 2>&1 | grep -v "Error" || true

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_logging_metric.pr_created' \
  "projects/$PROJECT_ID/metrics/security_patch_agent_prs_created" 2>&1 | grep -v "Error" || true

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_logging_metric.evidence_generated' \
  "projects/$PROJECT_ID/metrics/security_patch_agent_evidence_generated" 2>&1 | grep -v "Error" || true

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_logging_metric.api_requests' \
  "projects/$PROJECT_ID/metrics/security_patch_agent_api_requests" 2>&1 | grep -v "Error" || true

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_pubsub_subscription.scan_events_sub' \
  "projects/$PROJECT_ID/subscriptions/scan-events-subscription" 2>&1 | grep -v "Error" || true

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_pubsub_subscription.dead_letter_sub' \
  "projects/$PROJECT_ID/subscriptions/scan-events-dlq-subscription" 2>&1 | grep -v "Error" || true

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_container_cluster.primary[0]' \
  "projects/$PROJECT_ID/locations/$REGION/clusters/code-vulnerability-scanner" 2>&1 | grep -v "Error" || true

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_compute_network.vpc[0]' \
  "projects/$PROJECT_ID/global/networks/code-vulnerability-scanner-vpc" 2>&1 | grep -v "Error" || true

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_compute_subnetwork.subnet[0]' \
  "projects/$PROJECT_ID/regions/$REGION/subnetworks/code-vulnerability-scanner-subnet" 2>&1 | grep -v "Error" || true

terraform import -var="project_id=$PROJECT_ID" -var="region=$REGION" \
  'google_service_account.app_sa[0]' \
  "projects/$PROJECT_ID/serviceAccounts/security-patch-agent@$PROJECT_ID.iam.gserviceaccount.com" 2>&1 | grep -v "Error" || true

echo ""
echo "✅ Import complete!"
echo ""
echo "Running terraform plan to verify..."
terraform plan -var="project_id=$PROJECT_ID" -var="region=$REGION" -var="components=monitoring-only"

echo ""
echo "If plan shows no errors, state is fixed!"
echo "You can now run the GitHub Actions workflow with monitoring-only mode."
