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
    echo "  ./test_review_mode.sh"
    echo ""
    exit 1
fi

API_URL="http://34.171.214.25"

echo "=========================================="
echo "REVIEW Mode Test Setup"
echo "=========================================="
echo ""
echo "Project ID: $PROJECT_ID"
echo ""

# This script will:
# 1. Clone vulnerable-node-express
# 2. Create a test branch with a vulnerability
# 3. Push and create a PR
# 4. Trigger REVIEW mode scan

REPO_NAME="vulnerable-node-express"
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
git commit -m "Add test endpoint with SQL injection"

echo ""
echo "Step 3: Push branch"
echo "-------------------"
git push origin $BRANCH_NAME

echo ""
echo "Step 4: Create Pull Request"
echo "---------------------------"
gh pr create \
  --title "Test: Add SQL injection vulnerability" \
  --body "This PR intentionally adds a SQL injection vulnerability to test REVIEW mode.\n\n**Expected:** Security Patch Agent should comment with vulnerability details." \
  --head $BRANCH_NAME \
  --base main

PR_NUMBER=$(gh pr view --json number -q .number)

echo ""
echo "Step 5: Get API Key"
echo "-------------------"
API_KEY=$(kubectl get secret security-patch-agent-api-keys -n security-patch-agent --insecure-skip-tls-verify -o jsonpath='{.data.api-keys}' | base64 -d | cut -d',' -f1)

if [ -z "$API_KEY" ]; then
  echo "Error: Could not retrieve API key from Kubernetes secret"
  exit 1
fi

echo ""
echo "Step 6: Trigger REVIEW Mode Scan"
echo "---------------------------------"
REVIEW_RESPONSE=$(curl -s -X POST "$API_URL/scan" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d "{
    \"repo_url\": \"$REPO_URL\",
    \"mode\": \"review\",
    \"branch\": \"$BRANCH_NAME\"
  }")

echo "$REVIEW_RESPONSE" | jq .
REVIEW_SCAN_ID=$(echo "$REVIEW_RESPONSE" | jq -r .scan_id)

echo ""
echo "=========================================="
echo "REVIEW Mode Test Triggered"
echo "=========================================="
echo "PR Number: $PR_NUMBER"
echo "Scan ID: $REVIEW_SCAN_ID"
echo "Branch: $BRANCH_NAME"
echo ""
echo "Monitor progress:"
echo "1. PR: https://github.com/kannavkunal/$REPO_NAME/pull/$PR_NUMBER"
echo "2. Jobs: kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify | grep $REVIEW_SCAN_ID"
echo "3. Logs: kubectl logs -n security-patch-agent job/\$(kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify -o name | grep $REVIEW_SCAN_ID | head -1 | cut -d/ -f2) --insecure-skip-tls-verify"
echo ""

# Cleanup
cd /
rm -rf $TEST_DIR

echo "Waiting 2 minutes for scan to complete..."
sleep 120

echo ""
echo "Checking scan status in BigQuery:"
echo "---------------------------------"
bq query --project_id=$PROJECT_ID --use_legacy_sql=false "
SELECT
  scan_id,
  timestamp,
  scan_mode,
  status,
  vulnerabilities_found,
  pr_url
FROM \`$PROJECT_ID.security_scans.scans\`
WHERE scan_id = '$REVIEW_SCAN_ID'
"

echo ""
echo "Check the PR for comments: https://github.com/kannavkunal/$REPO_NAME/pull/$PR_NUMBER"
