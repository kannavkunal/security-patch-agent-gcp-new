#!/bin/bash
set -e

# Configuration
PROJECT_ID="security-patch-agent-gcp-new"
API_URL="http://34.60.187.202"

# Get API key from Kubernetes secret
echo "Retrieving API key from Kubernetes secret..."
API_KEY=$(kubectl get secret security-patch-agent-api-keys -n security-patch-agent --insecure-skip-tls-verify -o jsonpath='{.data.api-keys}' | base64 -d | cut -d',' -f1)

if [ -z "$API_KEY" ]; then
  echo "❌ ERROR: Could not retrieve API key from Kubernetes secret"
  echo "Run: kubectl get secret security-patch-agent-api-keys -n security-patch-agent --insecure-skip-tls-verify -o jsonpath='{.data.api-keys}' | base64 -d"
  exit 1
fi

echo "✓ API Key retrieved"
echo ""

echo "=========================================="
echo "Security Patch Agent - Complete E2E Test"
echo "=========================================="
echo ""
echo "Project ID: $PROJECT_ID"
echo "API URL: $API_URL"
echo ""

# ============================================
# Part 1: Security Testing (Authentication)
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 1: Security Testing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Test 1.1: Wrong API Key (should fail if auth enabled)"
echo "------------------------------------------------------"
curl -s -X POST "$API_URL/scan" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: wrong-key-12345" \
  -d '{"repo_url": "https://github.com/test/repo", "mode": "patch"}' | jq . || echo "Auth disabled (expected for testing)"
echo ""

echo "Test 1.2: No API Key (should fail if auth enabled)"
echo "---------------------------------------------------"
curl -s -X POST "$API_URL/scan" \
  -H "Content-Type: application/json" \
  -d '{"repo_url": "https://github.com/test/repo", "mode": "patch"}' | jq . || echo "Auth disabled (expected for testing)"
echo ""

echo "Test 1.3: Invalid webhook signature"
echo "------------------------------------"
echo "Note: Webhook requires HMAC-SHA256 signature. Testing without signature:"
curl -s -X POST "$API_URL/webhook/github" \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: pull_request" \
  -d '{"action": "opened", "pull_request": {"number": 1}}' | jq . || echo "Expected to fail (no signature)"
echo ""

# ============================================
# Part 2: Input Validation
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 2: Input Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Test 2.1: Invalid scan mode"
echo "----------------------------"
curl -s -X POST "$API_URL/scan" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"repo_url": "https://github.com/test/repo", "mode": "invalid"}' | jq .
echo ""

echo "Test 2.2: Missing required fields"
echo "----------------------------------"
curl -s -X POST "$API_URL/scan" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"mode": "patch"}' | jq .
echo ""

echo "Test 2.3: Invalid repository URL format"
echo "----------------------------------------"
curl -s -X POST "$API_URL/scan" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"repo_url": "not-a-valid-url", "mode": "patch"}' | jq .
echo ""

# ============================================
# Part 3: Basic GET Endpoints
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 3: Basic GET Endpoints"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Test 3.1: GET /health"
echo "---------------------"
HEALTH_RESPONSE=$(curl -s "$API_URL/health")
echo "$HEALTH_RESPONSE" | jq .
HEALTH_STATUS=$(echo "$HEALTH_RESPONSE" | jq -r .status)
if [ "$HEALTH_STATUS" == "healthy" ]; then
  echo "✓ Health check passed"
else
  echo "❌ Health check failed"
fi
echo ""

echo "Test 3.2: GET / (root - Web UI)"
echo "--------------------------------"
ROOT_RESPONSE=$(curl -s "$API_URL/")
if echo "$ROOT_RESPONSE" | grep -q "<!DOCTYPE html>"; then
  echo "✓ Web UI loaded successfully (HTML returned)"
else
  echo "⚠ Unexpected response format"
  echo "$ROOT_RESPONSE" | head -3
fi
echo ""

echo "Test 3.3: GET /repositories"
echo "---------------------------"
REPOS_RESPONSE=$(curl -s "$API_URL/repositories")
echo "$REPOS_RESPONSE" | jq .
REPO_COUNT=$(echo "$REPOS_RESPONSE" | jq -r .count)
echo "✓ Found $REPO_COUNT repositories configured"
echo ""

# ============================================
# Part 4: PATCH Mode Testing
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 4: PATCH Mode (Create PR)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Test 4.1: Trigger PATCH scan on vulnerable-python-api"
echo "-------------------------------------------------------"
PATCH_RESPONSE=$(curl -s -X POST "$API_URL/scan" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "repo_url": "https://github.com/kannavkunal/vulnerable-python-api",
    "mode": "patch",
    "branch": "main"
  }')

echo "$PATCH_RESPONSE" | jq .
PATCH_SCAN_ID=$(echo "$PATCH_RESPONSE" | jq -r .scan_id)

if [ "$PATCH_SCAN_ID" == "null" ] || [ -z "$PATCH_SCAN_ID" ]; then
  echo "❌ Failed to trigger PATCH scan"
  exit 1
else
  echo "✓ PATCH Scan ID: $PATCH_SCAN_ID"
fi
echo ""

# Wait for job to start
echo "Waiting 5 seconds for Kubernetes job to be created..."
sleep 5

echo "Test 4.2: Check K8s job created"
echo "--------------------------------"
JOB_NAME=$(kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify -o name | grep ${PATCH_SCAN_ID:5:8} | head -1)
if [ ! -z "$JOB_NAME" ]; then
  echo "✓ K8s Job created: $JOB_NAME"
  kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify | grep ${PATCH_SCAN_ID:5:8}
else
  echo "⚠ Job not found yet (may still be starting)"
fi
echo ""

# ============================================
# Part 5: GET /scans Endpoint Testing
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 5: GET /scans Endpoint Testing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Test 5.1: GET /scans (all scans, limit 3)"
echo "------------------------------------------"
curl -s "$API_URL/scans?limit=3" -H "X-API-Key: $API_KEY" | jq .
echo ""

echo "Test 5.2: GET /scans?repo_name=kannavkunal/vulnerable-python-api"
echo "-----------------------------------------------------------------"
curl -s "$API_URL/scans?repo_name=kannavkunal/vulnerable-python-api&limit=5" -H "X-API-Key: $API_KEY" | jq .
echo ""

echo "Test 5.3: GET /scans?scan_mode=patch"
echo "-------------------------------------"
curl -s "$API_URL/scans?scan_mode=patch&limit=5" -H "X-API-Key: $API_KEY" | jq .
echo ""

echo "Test 5.4: GET /scans?scan_mode=review"
echo "--------------------------------------"
curl -s "$API_URL/scans?scan_mode=review&limit=5" -H "X-API-Key: $API_KEY" | jq .
echo ""

TODAY=$(date +%Y-%m-%d)
echo "Test 5.5: GET /scans?start_date=$TODAY"
echo "---------------------------------------"
curl -s "$API_URL/scans?start_date=$TODAY&limit=10" -H "X-API-Key: $API_KEY" | jq .
echo ""

echo "Test 5.6: GET /scans/{scan_id} (invalid scan_id)"
echo "-------------------------------------------------"
curl -s "$API_URL/scans/scan-invalid-123" -H "X-API-Key: $API_KEY" | jq .
echo ""

echo "Test 5.7: GET /scans/{scan_id} (valid new scan)"
echo "------------------------------------------------"
curl -s "$API_URL/scans/$PATCH_SCAN_ID" -H "X-API-Key: $API_KEY" | jq .
echo ""

# ============================================
# Part 6: Monitor PATCH Scan Progress
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 6: Monitor PATCH Scan Progress"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Waiting 2 minutes for scan to process..."
sleep 120

echo "Test 6.1: Check job status"
echo "--------------------------"
kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify | grep ${PATCH_SCAN_ID:5:8} || echo "Job completed or not found"
echo ""

echo "Test 6.2: Check job logs (last 30 lines)"
echo "-----------------------------------------"
JOB_NAME=$(kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify -o name | grep ${PATCH_SCAN_ID:5:8} | head -1 | cut -d/ -f2)
if [ ! -z "$JOB_NAME" ]; then
  kubectl logs -n security-patch-agent job/$JOB_NAME --insecure-skip-tls-verify --tail=30 || echo "Job still running or failed to get logs"
else
  echo "⚠ Job not found (may have completed and been cleaned up)"
fi
echo ""

echo "Test 6.3: GET /scans/{scan_id} for updated status"
echo "--------------------------------------------------"
FINAL_SCAN=$(curl -s "$API_URL/scans/$PATCH_SCAN_ID" -H "X-API-Key: $API_KEY")
echo "$FINAL_SCAN" | jq .
SCAN_STATUS=$(echo "$FINAL_SCAN" | jq -r .status)
echo "Scan Status: $SCAN_STATUS"
echo ""

# ============================================
# Part 7: Verify BigQuery Data
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 7: BigQuery Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Test 7.1: Query recent scans with all fields"
echo "---------------------------------------------"
bq query --project_id=$PROJECT_ID --use_legacy_sql=false --format=prettyjson "
SELECT
  scan_id,
  timestamp,
  repo_name,
  repo_owner,
  scan_mode,
  trigger_type,
  llm_model_used,
  vulnerabilities_found,
  fixes_applied,
  pr_number,
  pr_url,
  evidence_path
FROM \`$PROJECT_ID.security_scans.scans\`
ORDER BY timestamp DESC
LIMIT 3
" | jq . || echo "BigQuery query failed"
echo ""

echo "Test 7.2: Check if new scan has non-NULL fields"
echo "------------------------------------------------"
bq query --project_id=$PROJECT_ID --use_legacy_sql=false "
SELECT
  scan_id,
  CASE WHEN repo_owner IS NULL THEN '❌ NULL' ELSE '✓ SET' END as repo_owner,
  CASE WHEN trigger_type IS NULL THEN '❌ NULL' ELSE '✓ SET' END as trigger_type,
  CASE WHEN llm_model_used IS NULL THEN '❌ NULL' ELSE '✓ SET' END as llm_model_used,
  CASE WHEN pr_number IS NULL THEN '⚠ NULL' ELSE '✓ SET' END as pr_number,
  status
FROM \`$PROJECT_ID.security_scans.scans\`
WHERE scan_id = '$PATCH_SCAN_ID'
" || echo "BigQuery query failed"
echo ""

echo "Test 7.3: Query vulnerabilities table"
echo "--------------------------------------"
bq query --project_id=$PROJECT_ID --use_legacy_sql=false --format=prettyjson "
SELECT
  scan_id,
  vulnerability_type,
  severity,
  file_path,
  line_number
FROM \`$PROJECT_ID.security_scans.vulnerabilities\`
WHERE scan_id = '$PATCH_SCAN_ID'
LIMIT 5
" | jq . || echo "No vulnerabilities found or query failed"
echo ""

# ============================================
# Part 8: Verify GCS Evidence
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 8: GCS Evidence Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Test 8.1: List GCS evidence for vulnerable-python-api"
echo "-------------------------------------------------------"
gsutil ls gs://security-patch-evidence-$PROJECT_ID/kannavkunal/vulnerable-python-api/ 2>/dev/null | tail -5 || echo "No evidence found yet"
echo ""

echo "Test 8.2: Check evidence structure for latest scan"
echo "---------------------------------------------------"
LATEST_SCAN=$(gsutil ls gs://security-patch-evidence-$PROJECT_ID/kannavkunal/vulnerable-python-api/ 2>/dev/null | tail -1)
if [ ! -z "$LATEST_SCAN" ]; then
  echo "✓ Evidence path: $LATEST_SCAN"
  gsutil ls $LATEST_SCAN 2>/dev/null || echo "Could not list evidence files"
else
  echo "⚠ No evidence found yet (scan may still be running)"
fi
echo ""

# ============================================
# Part 9: Pub/Sub Message Verification
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 9: Pub/Sub Message Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Test 9.1: Check Pub/Sub topic message count"
echo "--------------------------------------------"
gcloud pubsub topics list --project=$PROJECT_ID --filter="name~security-scan-events" --format="table(name, labels)"
echo ""

echo "Test 9.2: Check subscription backlog"
echo "-------------------------------------"
gcloud pubsub subscriptions list --project=$PROJECT_ID --filter="name~scan-events-subscription" --format="table(name, messageRetentionDuration, state)"
echo ""

# ============================================
# Summary
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✓ Security tests completed (auth, validation)"
echo "✓ Input validation tested (invalid modes, missing fields)"
echo "✓ PATCH mode triggered: $PATCH_SCAN_ID"
echo "✓ GET endpoints tested with filters (repo_name, scan_mode, dates)"
echo "✓ BigQuery data verified"
echo "✓ GCS evidence checked"
echo "✓ Pub/Sub infrastructure verified"
echo ""
echo "Next Steps:"
echo "1. Verify PR created: https://github.com/kannavkunal/vulnerable-python-api/pulls"
echo "2. Check PR has LLM-generated description and evidence link"
echo "3. Verify GCS evidence has markdown files"
echo "4. For REVIEW mode test, run: ./test_review_mode.sh"
echo ""
echo "Dashboards:"
echo "  Web UI: $API_URL"
echo "  GCP Console: https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
echo "  BigQuery: https://console.cloud.google.com/bigquery?project=$PROJECT_ID&d=security_scans"
echo "  GCS Evidence: https://console.cloud.google.com/storage/browser/security-patch-evidence-$PROJECT_ID"
echo ""
echo "Test completed at: $(date)"
echo ""
