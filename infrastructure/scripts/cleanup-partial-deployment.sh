#!/bin/bash
set -e

PROJECT_ID="${GCP_PROJECT_ID}"
REGION="${GCP_LOCATION:-us-central1}"

if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: GCP_PROJECT_ID environment variable is not set"
    exit 1
fi

echo "================================================"
echo "Cleaning Up Partial Deployment"
echo "================================================"
echo ""
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""
echo "⚠️  This will delete partially created resources"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

echo ""
echo "Deleting resources..."
echo ""

# Delete VPC (will fail if subnets exist, which is fine)
echo "1. Deleting VPC network..."
gcloud compute networks delete code-vulnerability-scanner-vpc \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  VPC not found or has dependencies"

# Delete Service Account
echo "2. Deleting service account..."
gcloud iam service-accounts delete \
  security-patch-agent@$PROJECT_ID.iam.gserviceaccount.com \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  Service account not found"

# Delete Logging Metrics
echo "3. Deleting logging metrics..."
gcloud logging metrics delete security_patch_agent_scans_completed \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  Metric not found"

gcloud logging metrics delete security_patch_agent_scans_failed \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  Metric not found"

gcloud logging metrics delete security_patch_agent_prs_created \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  Metric not found"

gcloud logging metrics delete security_patch_agent_evidence_generated \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  Metric not found"

gcloud logging metrics delete security_patch_agent_api_requests \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  Metric not found"

# Delete Pub/Sub Topics and Subscriptions
echo "4. Deleting Pub/Sub resources..."
gcloud pubsub subscriptions delete scan-events-subscription \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  Subscription not found"

gcloud pubsub subscriptions delete scan-events-dlq-subscription \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  DLQ subscription not found"

gcloud pubsub topics delete security-scan-events \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  Topic not found"

gcloud pubsub topics delete security-scan-events-dlq \
  --project=$PROJECT_ID \
  --quiet 2>/dev/null || echo "  ⏭️  DLQ topic not found"

echo ""
echo "================================================"
echo "Cleanup Complete!"
echo "================================================"
echo ""
echo "You can now run Terraform apply to create resources fresh."
echo ""
echo "Note: The following were NOT deleted (will be managed by Terraform):"
echo "  - GitHub token secret (already exists)"
echo "  - GitHub webhook secret (already exists)"
echo "  - GCS evidence bucket (if it exists)"
echo "  - Artifact Registry (if it exists)"
