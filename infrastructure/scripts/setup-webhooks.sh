#!/bin/bash
# Setup GitHub webhooks for all vulnerable repositories

set -e

echo "🔧 Setting up GitHub webhooks for vulnerable repositories"
echo "=========================================================="
echo ""

# Get LoadBalancer IP
echo "1️⃣ Getting LoadBalancer IP..."
EXTERNAL_IP=$(kubectl get svc security-patch-agent -n security-patch-agent \
  --insecure-skip-tls-verify \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$EXTERNAL_IP" ]; then
  echo "❌ Could not get LoadBalancer IP. Is the service deployed?"
  echo "   Run: kubectl get svc -n security-patch-agent --insecure-skip-tls-verify"
  exit 1
fi

echo "   ✅ LoadBalancer IP: $EXTERNAL_IP"
echo ""

# Get webhook secret
echo "2️⃣ Getting webhook secret from Secret Manager..."
WEBHOOK_SECRET=$(gcloud secrets versions access latest --secret=github-webhook-secret 2>/dev/null)

if [ -z "$WEBHOOK_SECRET" ]; then
  echo "❌ Webhook secret not found in Secret Manager!"
  echo ""
  echo "📝 To create it:"
  echo "   1. Generate: openssl rand -hex 32 > /tmp/webhook-secret.txt"
  echo "   2. Store: cat /tmp/webhook-secret.txt | gcloud secrets versions add github-webhook-secret --data-file=-"
  echo "   3. Clean up: rm /tmp/webhook-secret.txt"
  echo ""
  exit 1
fi

echo "   ✅ Webhook secret retrieved (length: ${#WEBHOOK_SECRET} chars)"
echo ""

# Get GitHub token
echo "3️⃣ Getting GitHub token..."
GITHUB_TOKEN=$(gcloud secrets versions access latest --secret=github-token 2>/dev/null)

if [ -z "$GITHUB_TOKEN" ]; then
  echo "❌ GitHub token not found in Secret Manager!"
  exit 1
fi

echo "   ✅ GitHub token retrieved"
echo ""

# Webhook URL
WEBHOOK_URL="http://${EXTERNAL_IP}/webhook/github"
echo "📡 Webhook URL: $WEBHOOK_URL"
echo ""

# Repositories to configure
REPOS=(
  "vulnerable-python-api"
  "vulnerable-node-service"
  "vulnerable-java-app"
  "vulnerable-go-microservice"
)

GITHUB_USER="kannavkunal"

echo "4️⃣ Configuring webhooks for ${#REPOS[@]} repositories..."
echo ""

for REPO in "${REPOS[@]}"; do
  echo "   📦 $GITHUB_USER/$REPO"

  # Check if webhook already exists
  EXISTING_HOOKS=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$GITHUB_USER/$REPO/hooks")

  HOOK_ID=$(echo "$EXISTING_HOOKS" | jq -r ".[] | select(.config.url == \"$WEBHOOK_URL\") | .id")

  if [ -n "$HOOK_ID" ]; then
    echo "      ⚠️  Webhook already exists (ID: $HOOK_ID)"
    echo "      🔄 Updating existing webhook..."

    # Update existing webhook
    RESPONSE=$(curl -s -w "\n%{http_code}" \
      -X PATCH \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$GITHUB_USER/$REPO/hooks/$HOOK_ID" \
      -d "{
        \"config\": {
          \"url\": \"$WEBHOOK_URL\",
          \"content_type\": \"json\",
          \"secret\": \"$WEBHOOK_SECRET\",
          \"insecure_ssl\": \"0\"
        },
        \"events\": [\"pull_request\"],
        \"active\": true
      }")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "200" ]; then
      echo "      ✅ Updated successfully"
    else
      echo "      ❌ Update failed (HTTP $HTTP_CODE)"
      echo "      Response: $BODY" | jq -r '.message // .' | head -3
    fi
  else
    echo "      ➕ Creating new webhook..."

    # Create new webhook
    RESPONSE=$(curl -s -w "\n%{http_code}" \
      -X POST \
      -H "Authorization: token $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$GITHUB_USER/$REPO/hooks" \
      -d "{
        \"config\": {
          \"url\": \"$WEBHOOK_URL\",
          \"content_type\": \"json\",
          \"secret\": \"$WEBHOOK_SECRET\",
          \"insecure_ssl\": \"0\"
        },
        \"events\": [\"pull_request\"],
        \"active\": true
      }")

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" = "201" ]; then
      NEW_HOOK_ID=$(echo "$BODY" | jq -r '.id')
      echo "      ✅ Created successfully (ID: $NEW_HOOK_ID)"

      # Test the webhook
      echo "      🧪 Testing webhook..."
      TEST_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$GITHUB_USER/$REPO/hooks/$NEW_HOOK_ID/tests")

      TEST_CODE=$(echo "$TEST_RESPONSE" | tail -n1)
      if [ "$TEST_CODE" = "204" ]; then
        echo "      ✅ Test ping sent"
      else
        echo "      ⚠️  Test ping may have failed"
      fi
    else
      echo "      ❌ Creation failed (HTTP $HTTP_CODE)"
      echo "      Response: $BODY" | jq -r '.message // .' | head -3
    fi
  fi

  echo ""
done

echo "=========================================================="
echo "✅ Webhook setup complete!"
echo ""
echo "📋 Summary:"
echo "   Webhook URL: $WEBHOOK_URL"
echo "   Repositories configured: ${#REPOS[@]}"
echo ""
echo "🔍 To verify webhooks in GitHub UI:"
for REPO in "${REPOS[@]}"; do
  echo "   https://github.com/$GITHUB_USER/$REPO/settings/hooks"
done
echo ""
echo "🧪 To test, create a PR in any of the repos and check:"
echo "   - GitHub webhook delivery status (Recent Deliveries)"
echo "   - Your API logs: kubectl logs -n security-patch-agent -l app=security-patch-agent -c security-patch-agent --insecure-skip-tls-verify"
