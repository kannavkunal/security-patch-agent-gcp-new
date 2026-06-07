#!/bin/bash
set -e

API_URL="http://34.171.214.25"

echo "=========================================="
echo "Security Patch Agent - E2E Deployment Test"
echo "=========================================="
echo ""

# Test 1: Health Check
echo "Test 1: Health Check"
echo "--------------------"
curl -s "$API_URL/health" | jq .
echo ""

# Test 2: Root endpoint
echo "Test 2: Root Endpoint"
echo "---------------------"
curl -s "$API_URL/" | jq .
echo ""

# Test 3: PATCH Mode - Create PR with automated fixes
echo "Test 3: PATCH Mode (vulnerable-java-api)"
echo "-----------------------------------------"
PATCH_RESPONSE=$(curl -s -X POST "$API_URL/scan" \
  -H "Content-Type: application/json" \
  -d '{
    "repo_url": "https://github.com/kannavkunal/vulnerable-java-api",
    "mode": "patch",
    "branch": "main"
  }')

echo "$PATCH_RESPONSE" | jq .
PATCH_SCAN_ID=$(echo "$PATCH_RESPONSE" | jq -r .scan_id)
echo "PATCH Scan ID: $PATCH_SCAN_ID"
echo ""

# Test 4: REVIEW Mode - Comment on existing PR
echo "Test 4: REVIEW Mode (vulnerable-node-express)"
echo "----------------------------------------------"
echo "NOTE: First create a test PR on vulnerable-node-express manually, then run:"
echo 'curl -X POST http://34.171.214.25/scan -H "Content-Type: application/json" -d '"'"'{"repo_url": "https://github.com/kannavkunal/vulnerable-node-express", "mode": "review", "branch": "test-branch"}'"'"''
echo ""

# Wait for PATCH scan to process
echo "Waiting 30 seconds for PATCH scan to start processing..."
sleep 30

# Test 5: GET /scans - List all scans
echo "Test 5: GET /scans - List all scans (limit 5)"
echo "---------------------------------------------"
curl -s "$API_URL/scans?limit=5" | jq .
echo ""

# Test 6: GET /scans - Filter by repo_name
echo "Test 6: GET /scans - Filter by repo_name (vulnerable-java-api)"
echo "---------------------------------------------------------------"
curl -s "$API_URL/scans?repo_name=kannavkunal/vulnerable-java-api&limit=3" | jq .
echo ""

# Test 7: GET /scans - Filter by scan_mode
echo "Test 7: GET /scans - Filter by scan_mode (patch)"
echo "-------------------------------------------------"
curl -s "$API_URL/scans?scan_mode=patch&limit=3" | jq .
echo ""

# Test 8: GET /scans - Filter by date range
echo "Test 8: GET /scans - Filter by date (today)"
echo "--------------------------------------------"
TODAY=$(date +%Y-%m-%d)
curl -s "$API_URL/scans?start_date=$TODAY&limit=5" | jq .
echo ""

# Test 9: GET /scans/{scan_id} - Get specific scan
echo "Test 9: GET /scans/{scan_id} - Get specific scan"
echo "-------------------------------------------------"
echo "Getting details for scan: $PATCH_SCAN_ID"
curl -s "$API_URL/scans/$PATCH_SCAN_ID" | jq .
echo ""

# Test 10: Check K8s job created
echo "Test 10: Check K8s Job Status"
echo "------------------------------"
kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify --sort-by=.metadata.creationTimestamp | tail -5
echo ""

# Test 11: Check recent logs
echo "Test 11: Check Recent API Logs"
echo "-------------------------------"
kubectl logs -n security-patch-agent deployment/security-patch-agent -c api --tail=20 --insecure-skip-tls-verify
echo ""

echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "✓ Health check"
echo "✓ PATCH mode triggered (check PR on vulnerable-java-api)"
echo "✓ GET /scans endpoints tested with filters"
echo "✓ K8s job status checked"
echo ""
echo "Next Steps:"
echo "1. Monitor the K8s job: kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify -w"
echo "2. Check job logs: kubectl logs -n security-patch-agent job/scan-<job-id> --insecure-skip-tls-verify"
echo "3. Verify PR created on: https://github.com/kannavkunal/vulnerable-java-api/pulls"
echo "4. Check BigQuery: SELECT * FROM \`compact-orb-498606-f9.security_scans.scans\` ORDER BY timestamp DESC LIMIT 5"
echo "5. Check GCS evidence: gsutil ls gs://security-patch-evidence-compact-orb-498606-f9/kannavkunal/vulnerable-java-api/"
echo ""
