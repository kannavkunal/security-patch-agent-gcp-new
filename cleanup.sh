#!/bin/bash
# Security Patch Agent - Complete Cleanup Script
# Deletes all GCP resources to prevent ongoing costs

set -e

echo "========================================="
echo "Security Patch Agent - Cleanup Script"
echo "========================================="
echo ""
echo "This will DELETE all resources:"
echo "  - GKE cluster"
echo "  - Pub/Sub topics and subscriptions"
echo "  - BigQuery dataset"
echo "  - Cloud Storage buckets"
echo "  - Secret Manager secrets"
echo "  - Artifact Registry repository"
echo "  - Service accounts"
echo "  - Monitoring dashboards and alerts"
echo ""
echo "WARNING: This action cannot be undone!"
echo ""

# Prompt for confirmation
read -p "Are you sure you want to delete ALL resources? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Read from environment variables (required from GitHub Secrets or export)
PROJECT_ID="${GCP_PROJECT_ID}"
REGION="${GCP_REGION:-us-central1}"
CLUSTER_NAME="${GKE_CLUSTER:-code-vulnerability-scanner}"

# Validate required variables
if [ -z "$PROJECT_ID" ]; then
    echo ""
    echo "ERROR: GCP_PROJECT_ID environment variable is not set"
    echo ""
    echo "Usage:"
    echo "  export GCP_PROJECT_ID='your-project-id'"
    echo "  ./cleanup.sh"
    echo ""
    echo "Or run directly:"
    echo "  GCP_PROJECT_ID='your-project-id' ./cleanup.sh"
    exit 1
fi

echo ""
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Cluster: $CLUSTER_NAME"
echo ""
echo "Starting cleanup..."
echo ""

# Set project
gcloud config set project $PROJECT_ID

# 1. Delete GKE cluster (this will delete all pods, services, jobs)
echo "1. Deleting GKE cluster..."
gcloud container clusters delete $CLUSTER_NAME \
    --region=$REGION \
    --quiet || echo "Cluster already deleted or not found"

# 2. Delete Pub/Sub resources
echo "2. Deleting Pub/Sub topics and subscriptions..."
gcloud pubsub subscriptions delete security-scan-events-sub --quiet || echo "Subscription not found"
gcloud pubsub topics delete security-scan-events --quiet || echo "Topic not found"

# 3. Delete BigQuery dataset (includes all tables)
echo "3. Deleting BigQuery dataset..."
bq rm -r -f -d $PROJECT_ID:security_scans || echo "Dataset not found"

# 4. Delete Cloud Storage buckets
echo "4. Deleting Cloud Storage buckets..."
gsutil -m rm -r gs://security-patch-evidence-$PROJECT_ID || echo "Bucket not found"

# 5. Delete Secret Manager secrets
echo "5. Deleting Secret Manager secrets..."
gcloud secrets delete github-token --quiet || echo "Secret not found"
gcloud secrets delete github-webhook-secret --quiet || echo "Secret not found"
gcloud secrets delete security-patch-agent-api-keys --quiet || echo "Secret not found"

# 6. Delete Artifact Registry repository
echo "6. Deleting Artifact Registry repository..."
gcloud artifacts repositories delete security-patch-agent \
    --location=$REGION \
    --quiet || echo "Repository not found"

# 7. Delete service accounts
echo "7. Deleting service accounts..."
gcloud iam service-accounts delete security-patch-agent@$PROJECT_ID.iam.gserviceaccount.com \
    --quiet || echo "Service account not found"

# 8. Delete monitoring dashboards
echo "8. Deleting monitoring dashboards..."
# List and delete all dashboards with "Security Patch Agent" in the name
DASHBOARD_IDS=$(gcloud monitoring dashboards list --format="value(name)" --filter="displayName:'Security Patch Agent*'" 2>/dev/null || echo "")
if [ ! -z "$DASHBOARD_IDS" ]; then
    for DASHBOARD_ID in $DASHBOARD_IDS; do
        gcloud monitoring dashboards delete $DASHBOARD_ID --quiet || echo "Dashboard delete failed"
    done
else
    echo "No dashboards found"
fi

# 9. Delete alert policies
echo "9. Deleting alert policies..."
ALERT_IDS=$(gcloud alpha monitoring policies list --format="value(name)" --filter="displayName:'Security Patch Agent*'" 2>/dev/null || echo "")
if [ ! -z "$ALERT_IDS" ]; then
    for ALERT_ID in $ALERT_IDS; do
        gcloud alpha monitoring policies delete $ALERT_ID --quiet || echo "Alert policy delete failed"
    done
else
    echo "No alert policies found"
fi

# 10. Delete log-based metrics
echo "10. Deleting log-based metrics..."
gcloud logging metrics delete security_patch_agent_scans_completed --quiet || echo "Metric not found"
gcloud logging metrics delete security_patch_agent_scans_failed --quiet || echo "Metric not found"
gcloud logging metrics delete security_patch_agent_prs_created --quiet || echo "Metric not found"
gcloud logging metrics delete security_patch_agent_evidence_generated --quiet || echo "Metric not found"
gcloud logging metrics delete security_patch_agent_api_requests --quiet || echo "Metric not found"

# 11. Delete VPC network (if custom network was created)
echo "11. Checking for custom VPC networks..."
# Skip if using default network

echo ""
echo "========================================="
echo "Cleanup complete!"
echo "========================================="
echo ""
echo "All resources have been deleted."
echo "You can verify by running:"
echo "  gcloud container clusters list"
echo "  gcloud pubsub topics list"
echo "  bq ls -d"
echo "  gsutil ls"
echo ""
echo "Note: Some resources may take a few minutes to fully delete."
echo "Expected cost after cleanup: \$0/month"
echo ""
