#!/bin/bash
set -e

# Configuration
PROJECT_ID="security-patch-agent-gcp-new"
API_URL="http://34.60.187.202"

echo "=========================================="
echo "REVIEW Mode Test"
echo "=========================================="
echo ""
echo "Project ID: $PROJECT_ID"
echo "API URL: $API_URL"
echo ""

# Get API key
echo "Retrieving API key from Kubernetes secret..."
API_KEY=$(kubectl get secret security-patch-agent-api-keys -n security-patch-agent --insecure-skip-tls-verify -o jsonpath='{.data.api-keys}' | base64 -d | cut -d',' -f1)

if [ -z "$API_KEY" ]; then
  echo "❌ ERROR: Could not retrieve API key"
  exit 1
fi
echo "✓ API Key retrieved"
echo ""

# This script will:
# 1. Clone vulnerable-node-service
# 2. Create a test branch with a vulnerability
# 3. Push and create a PR
# 4. Trigger REVIEW mode scan

REPO_NAME="vulnerable-node-service"
REPO_URL="https://github.com/kannavkunal/$REPO_NAME"
TEST_DIR="/tmp/test-review-$$"

echo "Step 1: Clone repository"
echo "------------------------"
git clone $REPO_URL $TEST_DIR
cd $TEST_DIR

echo ""
echo "Step 2: Create test branch with vulnerability"
echo "----------------------------------------------"
BRANCH_NAME="test/add-sql-injection-$(date +%Y%m%d-%H%M%S)"
git checkout -b $BRANCH_NAME

# Add a vulnerable endpoint
cat > test-vuln.js << 'EOF'
const express = require('express');
const mysql = require('mysql');

const app = express();

// SQL Injection vulnerability
app.get('/user/:id', (req, res) => {
  const connection = mysql.createConnection({
    host: 'localhost',
    user: 'root',
    password: 'password',
    database: 'test'
  });

  // VULNERABLE: Direct string concatenation
  const query = "SELECT * FROM users WHERE id = " + req.params.id;

  connection.query(query, (err, results) => {
    if (err) throw err;
    res.json(results);
  });
});

app.listen(3000);
EOF

git add test-vuln.js
git commit -m "Add test endpoint with SQL injection vulnerability"

echo ""
echo "Step 3: Push branch"
echo "-------------------"
git push origin $BRANCH_NAME

echo ""
echo "Step 4: Create Pull Request"
echo "---------------------------"
gh pr create \
  --title "Test: Add SQL injection vulnerability for REVIEW mode" \
  --body "This PR intentionally adds a SQL injection vulnerability to test REVIEW mode.

**Expected:** Security Patch Agent should:
- Detect the SQL injection vulnerability
- Post a comment on this PR with vulnerability details
- Only report NEW vulnerabilities (not in base branch)
- Store results in BigQuery" \
  --head $BRANCH_NAME \
  --base main

PR_NUMBER=$(gh pr view --json number -q .number)

echo ""
echo "Step 5: Trigger REVIEW Mode Scan"
echo "---------------------------------"
REVIEW_RESPONSE=$(curl -s -X POST "$API_URL/scan" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{
    \"repo_url\": \"$REPO_URL\",
    \"mode\": \"review\",
    \"branch\": \"$BRANCH_NAME\",
    \"pr_number\": $PR_NUMBER
  }")

echo "$REVIEW_RESPONSE" | jq .
REVIEW_SCAN_ID=$(echo "$REVIEW_RESPONSE" | jq -r .scan_id)

if [ "$REVIEW_SCAN_ID" == "null" ] || [ -z "$REVIEW_SCAN_ID" ]; then
  echo "❌ Failed to trigger REVIEW scan"
  cd /
  rm -rf $TEST_DIR
  exit 1
fi

echo ""
echo "=========================================="
echo "REVIEW Mode Test Triggered"
echo "=========================================="
echo "✓ PR Number: $PR_NUMBER"
echo "✓ Scan ID: $REVIEW_SCAN_ID"
echo "✓ Branch: $BRANCH_NAME"
echo ""
echo "Monitor progress:"
echo "1. PR: https://github.com/kannavkunal/$REPO_NAME/pull/$PR_NUMBER"
echo "2. Jobs: kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify | grep ${REVIEW_SCAN_ID:5:8}"
echo "3. Logs: kubectl logs -n security-patch-agent job/\$(kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify -o name | grep ${REVIEW_SCAN_ID:5:8} | head -1 | cut -d/ -f2) --insecure-skip-tls-verify --tail=50"
echo ""

# Cleanup temp directory
cd /
rm -rf $TEST_DIR

echo "Waiting 2 minutes for scan to complete..."
sleep 120

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Verification Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Step 6.1: Check job status"
echo "--------------------------"
kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify | grep ${REVIEW_SCAN_ID:5:8} || echo "Job completed or not found"
echo ""

echo "Step 6.2: Check scan status in BigQuery"
echo "----------------------------------------"
bq query --project_id=$PROJECT_ID --use_legacy_sql=false --format=prettyjson "
SELECT
  scan_id,
  timestamp,
  scan_mode,
  status,
  vulnerabilities_found,
  pr_number,
  pr_url,
  evidence_path
FROM \`$PROJECT_ID.security_scans.scans\`
WHERE scan_id = '$REVIEW_SCAN_ID'
" | jq . || echo "Query failed"
echo ""

echo "Step 6.3: Check vulnerabilities found (NEW only)"
echo "-------------------------------------------------"
bq query --project_id=$PROJECT_ID --use_legacy_sql=false --format=prettyjson "
SELECT
  vulnerability_type,
  severity,
  file_path,
  line_number,
  description
FROM \`$PROJECT_ID.security_scans.vulnerabilities\`
WHERE scan_id = '$REVIEW_SCAN_ID'
LIMIT 10
" | jq . || echo "No vulnerabilities or query failed"
echo ""

echo "Step 6.4: GET /scans/{scan_id} via API"
echo "---------------------------------------"
curl -s "$API_URL/scans/$REVIEW_SCAN_ID" -H "X-API-Key: $API_KEY" | jq .
echo ""

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Manual Verification Required"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Check the PR for security comments:"
echo "   https://github.com/kannavkunal/$REPO_NAME/pull/$PR_NUMBER"
echo ""
echo "2. Verify the comment contains:"
echo "   - SQL injection vulnerability details"
echo "   - File path: test-vuln.js"
echo "   - Line number where vulnerability exists"
echo "   - Link to GCS evidence"
echo ""
echo "3. Check GCS evidence:"
EVIDENCE_PATH="gs://security-patch-evidence-$PROJECT_ID/kannavkunal/$REPO_NAME/$REVIEW_SCAN_ID/"
echo "   gsutil ls $EVIDENCE_PATH"
echo ""
echo "4. Close the test PR after verification:"
echo "   gh pr close $PR_NUMBER -d"
echo ""
echo "Test completed at: $(date)"
echo ""
