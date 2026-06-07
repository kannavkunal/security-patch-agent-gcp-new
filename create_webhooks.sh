#!/bin/bash
#
# Create GitHub Webhooks for Security Patch Agent
#
# This script creates webhooks for all 4 repositories to enable REVIEW mode
#

set -e

echo "🔗 Creating GitHub Webhooks for Security Patch Agent"
echo "=================================================="
echo ""

# Get webhook secret from Secret Manager
echo "1️⃣  Retrieving webhook secret from Secret Manager..."
WEBHOOK_SECRET=$(gcloud secrets versions access latest --secret="github-webhook-secret" --project="security-patch-agent-gcp-new")
echo "   ✅ Webhook secret retrieved"
echo ""

# Configuration
WEBHOOK_URL="http://34.60.187.202/webhook/github"
GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-token" --project="security-patch-agent-gcp-new")

# Repositories to configure (from VULNERABLE_REPOS ConfigMap)
REPOS=(
    "kannavkunal/vulnerable-python-api"
    "kannavkunal/vulnerable-node-service"
    "kannavkunal/vulnerable-go-microservice"
    "kannavkunal/vulnerable-java-app"
)

echo "2️⃣  Creating webhooks for ${#REPOS[@]} repositories..."
echo ""

# Counter
SUCCESS=0
FAILED=0

for REPO in "${REPOS[@]}"; do
    echo "   📦 Repository: $REPO"

    # Create webhook
    RESPONSE=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$REPO/hooks" \
        -d "{
            \"name\": \"web\",
            \"active\": true,
            \"events\": [\"pull_request\"],
            \"config\": {
                \"url\": \"$WEBHOOK_URL\",
                \"content_type\": \"json\",
                \"secret\": \"$WEBHOOK_SECRET\",
                \"insecure_ssl\": \"1\"
            }
        }")

    # Check if successful
    WEBHOOK_ID=$(echo "$RESPONSE" | jq -r '.id // empty')
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message // empty')

    if [ -n "$WEBHOOK_ID" ]; then
        echo "      ✅ Webhook created (ID: $WEBHOOK_ID)"
        echo "      🔗 URL: $WEBHOOK_URL"
        echo "      📋 Events: pull_request"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "      ❌ Failed: $ERROR_MSG"

        # Check if webhook already exists
        if echo "$ERROR_MSG" | grep -q "already exists\|Hook already exists"; then
            echo "      ℹ️  Webhook already configured"
            SUCCESS=$((SUCCESS + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    fi
    echo ""
done

echo "=================================================="
echo "✅ Webhook Creation Complete!"
echo ""
echo "Summary:"
echo "  • Successful: $SUCCESS/${#REPOS[@]}"
echo "  • Failed: $FAILED/${#REPOS[@]}"
echo ""

if [ $SUCCESS -eq ${#REPOS[@]} ]; then
    echo "🎉 All webhooks configured successfully!"
    echo ""
    echo "Next Steps:"
    echo "  1. Open a test PR in any repository"
    echo "  2. System will automatically scan for NEW vulnerabilities"
    echo "  3. Comment will be posted on PR with findings"
else
    echo "⚠️  Some webhooks failed to create"
    echo "   Check error messages above for details"
fi

echo ""
echo "Webhook Configuration:"
echo "  • URL: $WEBHOOK_URL"
echo "  • Events: pull_request"
echo "  • Secret: ✅ Configured"
echo ""
