#!/bin/bash
# Quick test with existing vulnerable-python-api repo

set -e

# Read from environment variables (required)
PROJECT_ID="${GCP_PROJECT_ID}"

# Validate required variables
if [ -z "$PROJECT_ID" ]; then
    echo ""
    echo "ERROR: GCP_PROJECT_ID environment variable is not set"
    echo ""
    echo "Usage:"
    echo "  export GCP_PROJECT_ID='your-project-id'"
    echo "  ./quick_test.sh"
    echo ""
    exit 1
fi

API_URL="http://34.171.214.25"

# Get API key from Kubernetes secret
API_KEY=$(kubectl get secret security-patch-agent-api-keys -n security-patch-agent --insecure-skip-tls-verify -o jsonpath='{.data.api-keys}' | base64 -d | cut -d',' -f1)

if [ -z "$API_KEY" ]; then
  echo "Error: Could not retrieve API key from Kubernetes secret"
  echo "Run: kubectl get secret security-patch-agent-api-keys -n security-patch-agent -o jsonpath='{.data.api-keys}' | base64 -d"
  exit 1
fi

echo "Testing PATCH mode with vulnerable-python-api..."
RESPONSE=$(curl -s -X POST "$API_URL/scan" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "repo_url": "https://github.com/kannavkunal/vulnerable-python-api",
    "mode": "patch",
    "branch": "main"
  }')

echo "$RESPONSE" | jq .
SCAN_ID=$(echo "$RESPONSE" | jq -r .scan_id)

echo ""
echo "Scan ID: $SCAN_ID"
echo ""
echo "Monitor job:"
kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify | grep ${SCAN_ID:5:8}

echo ""
echo "Wait 2 minutes then check:"
echo "1. PR: https://github.com/kannavkunal/vulnerable-python-api/pulls"
echo "2. BigQuery: bq query --use_legacy_sql=false 'SELECT * FROM \`$PROJECT_ID.security_scans.scans\` WHERE scan_id=\"$SCAN_ID\"'"
echo "3. GCS: gsutil ls gs://security-patch-evidence-$PROJECT_ID/kannavkunal/vulnerable-python-api/"
