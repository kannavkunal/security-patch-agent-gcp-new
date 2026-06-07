#!/bin/bash
set -e

PROJECT_ID="compact-orb-498606-f9"

echo "================================================"
echo "Creating Log-Based Metrics in Cloud Logging"
echo "================================================"
echo ""

# Create log-based metric for API requests
echo "1. Creating metric: api_requests_total..."
gcloud logging metrics create api_requests_total \
    --description="Total API requests to /analyze endpoint" \
    --log-filter='resource.type="k8s_container"
resource.labels.namespace_name="security-patch-agent"
jsonPayload.path="/analyze"' \
    --project=$PROJECT_ID || echo "Metric may already exist"

# Create log-based metric for authentication failures
echo "2. Creating metric: auth_failures_total..."
gcloud logging metrics create auth_failures_total \
    --description="Failed authentication attempts (401)" \
    --log-filter='resource.type="k8s_container"
resource.labels.namespace_name="security-patch-agent"
jsonPayload.status_code=401' \
    --project=$PROJECT_ID || echo "Metric may already exist"

# Create log-based metric for rate limit hits
echo "3. Creating metric: rate_limit_hits_total..."
gcloud logging metrics create rate_limit_hits_total \
    --description="Rate limit violations (429)" \
    --log-filter='resource.type="k8s_container"
resource.labels.namespace_name="security-patch-agent"
jsonPayload.status_code=429' \
    --project=$PROJECT_ID || echo "Metric may already exist"

# Create log-based metric for vulnerabilities detected
echo "4. Creating metric: vulnerabilities_detected_total..."
gcloud logging metrics create vulnerabilities_detected_total \
    --description="Total vulnerabilities detected by AI" \
    --log-filter='resource.type="k8s_container"
resource.labels.namespace_name="security-patch-agent"
jsonPayload.is_vulnerable=true' \
    --project=$PROJECT_ID || echo "Metric may already exist"

echo ""
echo "================================================"
echo "Log-Based Metrics Created!"
echo "================================================"
echo ""
echo "View metrics in Cloud Monitoring:"
echo "https://console.cloud.google.com/logs/metrics?project=$PROJECT_ID"
echo ""
