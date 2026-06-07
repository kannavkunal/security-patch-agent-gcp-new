#!/bin/bash
# Fix 409 errors by deleting conflicting resources
# These will be recreated by Terraform with proper state tracking

set -e

PROJECT_ID=$(gcloud config get-value project)

echo "🗑️  Deleting conflicting resources from GCP..."
echo "Project: $PROJECT_ID"
echo ""

# Delete logging metrics (causing 409 errors)
echo "Deleting logging metrics..."
gcloud logging metrics delete security_patch_agent_scans_completed --quiet 2>&1 || echo "  Already deleted"
gcloud logging metrics delete security_patch_agent_scans_failed --quiet 2>&1 || echo "  Already deleted"
gcloud logging metrics delete security_patch_agent_prs_created --quiet 2>&1 || echo "  Already deleted"
gcloud logging metrics delete security_patch_agent_evidence_generated --quiet 2>&1 || echo "  Already deleted"
gcloud logging metrics delete security_patch_agent_api_requests --quiet 2>&1 || echo "  Already deleted"

# Delete Pub/Sub subscriptions (causing 409 errors)
echo ""
echo "Deleting Pub/Sub subscriptions..."
gcloud pubsub subscriptions delete scan-events-subscription --quiet 2>&1 || echo "  Already deleted"
gcloud pubsub subscriptions delete scan-events-dlq-subscription --quiet 2>&1 || echo "  Already deleted"

# Disable GKE deletion protection
echo ""
echo "Disabling GKE deletion protection..."
gcloud container clusters update code-vulnerability-scanner \
  --region=us-central1 \
  --no-deletion-protection 2>&1 || echo "  Cluster not found or already updated"

# Try to release subnet IP (if in use)
echo ""
echo "Releasing subnet IP addresses..."
gcloud compute addresses delete gk3-code-vulnerability-scanner-cd432b88-f03a1d60-pe \
  --region=us-central1 \
  --quiet 2>&1 || echo "  Address not found or already deleted"

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Next steps:"
echo "1. Go to GitHub Actions: https://github.com/kannavkunal/security-patch-agent-gcp/actions"
echo "2. Run 'Full Deployment' workflow with:"
echo "   - Deploy infrastructure: true"
echo "   - Infrastructure components: monitoring-only"
echo "   - Deploy application: true"
echo ""
echo "Terraform will recreate the deleted resources with proper state tracking."
