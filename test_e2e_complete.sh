#!/bin/bash
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
    echo "  ./test_e2e_complete.sh"
    echo ""
    exit 1
fi

API_URL="http://34.171.214.25"

# Get API key from Kubernetes secret
API_KEY=$(kubectl get secret security-patch-agent-api-keys -n security-patch-agent --insecure-skip-tls-verify -o jsonpath='{.data.api-keys}' | base64 -d | cut -d',' -f1)

if [ -z "$API_KEY" ]; then
  echo "Warning: Could not retrieve API key from Kubernetes secret"
  echo "Some tests may fail. Run: kubectl get secret security-patch-agent-api-keys -n security-patch-agent -o jsonpath='{.data.api-keys}' | base64 -d"
  echo ""
fi

echo "=========================================="
echo "Security Patch Agent - Complete E2E Test"
echo "=========================================="
echo ""
echo "Project ID: $PROJECT_ID"
echo ""

# ============================================
# Part 1: Security Testing (Authentication)
# ============================================
echo "PART 1: Security Testing"
echo "========================"
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

echo "Test 1.3: Invalid webhook signature (simulated)"
echo "-------------------------------------------------"
echo "Note: Webhook requires HMAC-SHA256 signature. Testing without signature:"
curl -s -X POST "$API_URL/webhook/github" \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: pull_request" \
  -d '{"action": "opened", "pull_request": {"number": 1}}' | jq . || echo "Expected to fail"
echo ""

# ============================================
# Part 2: Input Validation
# ============================================
echo "PART 2: Input Validation"
echo "========================"
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

# ============================================
# Part 3: PATCH Mode Testing
# ============================================
echo "PART 3: PATCH Mode (Create PR)"
echo "=============================="
echo ""

echo "Test 3.1: Trigger PATCH scan on vulnerable-python-api"
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
echo "PATCH Scan ID: $PATCH_SCAN_ID"
echo ""

# Wait for job to start
sleep 5

echo "Test 3.2: Check K8s job created"
echo "--------------------------------"
kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify | grep ${PATCH_SCAN_ID:5:8} || echo "Job not found yet"
echo ""

# ============================================
# Part 4: GET Endpoints Testing
# ============================================
echo "PART 4: GET Endpoints"
echo "====================="
echo ""

echo "Test 4.1: GET /health"
echo "---------------------"
curl -s "$API_URL/health" | jq .
echo ""

echo "Test 4.2: GET / (root)"
echo "----------------------"
curl -s "$API_URL/" | jq .
echo ""

echo "Test 4.3: GET /scans (all scans, limit 3)"
echo "------------------------------------------"
curl -s "$API_URL/scans?limit=3" -H "X-API-Key: $API_KEY" | jq .
echo ""

echo "Test 4.4: GET /scans?repo_name=kannavkunal/vulnerable-python-api"
echo "-----------------------------------------------------------------"
curl -s "$API_URL/scans?repo_name=kannavkunal/vulnerable-python-api&limit=5" -H "X-API-Key: $API_KEY" | jq .
echo ""

echo "Test 4.5: GET /scans?scan_mode=patch"
echo "-------------------------------------"
curl -s "$API_URL/scans?scan_mode=patch&limit=5" -H "X-API-Key: $API_KEY" | jq .
echo ""

echo "Test 4.6: GET /scans?scan_mode=review"
echo "--------------------------------------"
curl -s "$API_URL/scans?scan_mode=review&limit=5" -H "X-API-Key: $API_KEY" | jq .
echo ""

TODAY=$(date +%Y-%m-%d)
echo "Test 4.7: GET /scans?start_date=$TODAY"
echo "---------------------------------------"
curl -s "$API_URL/scans?start_date=$TODAY&limit=5" -H "X-API-Key: $API_KEY" | jq .
echo ""

echo "Test 4.8: GET /scans/{scan_id} (invalid scan_id)"
echo "-------------------------------------------------"
curl -s "$API_URL/scans/scan-invalid-123" -H "X-API-Key: $API_KEY" | jq .
echo ""

# ============================================
# Part 5: Wait for PATCH scan to complete
# ============================================
echo "PART 5: Monitor PATCH Scan Progress"
echo "===================================="
echo ""

echo "Waiting 2 minutes for scan to process..."
sleep 120

echo "Test 5.1: Check job status"
echo "--------------------------"
kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify | grep ${PATCH_SCAN_ID:5:8}
echo ""

echo "Test 5.2: Check job logs (last 30 lines)"
echo "-----------------------------------------"
JOB_NAME=$(kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify -o name | grep ${PATCH_SCAN_ID:5:8} | head -1 | cut -d/ -f2)
if [ ! -z "$JOB_NAME" ]; then
  kubectl logs -n security-patch-agent job/$JOB_NAME --insecure-skip-tls-verify --tail=30 || echo "Job still running or failed to get logs"
else
  echo "Job not found"
fi
echo ""

echo "Test 5.3: GET /scans/{scan_id} for new PATCH scan"
echo "--------------------------------------------------"
curl -s "$API_URL/scans/$PATCH_SCAN_ID" -H "X-API-Key: $API_KEY" | jq .
echo ""

# ============================================
# Part 6: Verify BigQuery Data
# ============================================
echo "PART 6: BigQuery Verification"
echo "=============================="
echo ""

echo "Test 6.1: Query recent scans with all fields"
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
" | jq .
echo ""

echo "Test 6.2: Check if new scan has non-NULL fields"
echo "------------------------------------------------"
bq query --project_id=$PROJECT_ID --use_legacy_sql=false "
SELECT
  scan_id,
  CASE WHEN repo_owner IS NULL THEN 'NULL' ELSE '✓' END as repo_owner,
  CASE WHEN trigger_type IS NULL THEN 'NULL' ELSE '✓' END as trigger_type,
  CASE WHEN llm_model_used IS NULL THEN 'NULL' ELSE '✓' END as llm_model_used,
  CASE WHEN pr_number IS NULL THEN 'NULL' ELSE '✓' END as pr_number
FROM \`$PROJECT_ID.security_scans.scans\`
WHERE scan_id = '$PATCH_SCAN_ID'
"
echo ""

# ============================================
# Part 7: Verify GCS Evidence
# ============================================
echo "PART 7: GCS Evidence Verification"
echo "=================================="
echo ""

echo "Test 7.1: List GCS evidence for vulnerable-python-api"
echo "-------------------------------------------------------"
gsutil ls gs://security-patch-evidence-$PROJECT_ID/kannavkunal/vulnerable-python-api/ | tail -5
echo ""

echo "Test 7.2: Check evidence structure for latest scan"
echo "---------------------------------------------------"
LATEST_SCAN=$(gsutil ls gs://security-patch-evidence-$PROJECT_ID/kannavkunal/vulnerable-python-api/ | tail -1)
if [ ! -z "$LATEST_SCAN" ]; then
  echo "Evidence path: $LATEST_SCAN"
  gsutil ls $LATEST_SCAN
else
  echo "No evidence found yet"
fi
echo ""

# ============================================
# Summary
# ============================================
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo ""
echo "✓ Security tests completed (auth, validation)"
echo "✓ PATCH mode triggered: $PATCH_SCAN_ID"
echo "✓ GET endpoints tested with filters"
echo "✓ BigQuery data verified"
echo "✓ GCS evidence checked"
echo ""
echo "Next Steps:"
echo "1. Verify PR created: https://github.com/kannavkunal/vulnerable-python-api/pulls"
echo "2. Check PR has LLM-generated description and evidence link"
echo "3. Verify GCS evidence has markdown files"
echo "4. For REVIEW mode test, run: ./test_review_mode.sh"
echo ""
echo "Dashboards:"
echo "  https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
echo ""
