#!/bin/bash

# Get API Key from deployed pod
# This extracts the API key that was deployed from GitHub Secrets

set -e

echo "Retrieving API key from deployed pod..."
echo ""

# Get the API keys from the secret
API_KEYS=$(gcloud logging read \
    'resource.type=k8s_container
     resource.labels.namespace_name=security-patch-agent
     jsonPayload.message=~"API_KEYS"' \
    --limit=1 \
    --project=compact-orb-498606-f9 \
    --format=json 2>/dev/null | jq -r '.[0].jsonPayload.message' || echo "")

if [ -n "$API_KEYS" ]; then
    echo "Found API keys in logs: $API_KEYS"
else
    echo "Could not find API keys in logs. Checking pod environment..."

    # Alternative: Read from Kubernetes secret directly
    # Requires kubectl access
    export USE_GKE_GCLOUD_AUTH_PLUGIN=True

    # Get credentials
    gcloud container clusters get-credentials code-vulnerability-scanner \
        --region=us-central1 \
        --project=compact-orb-498606-f9 2>/dev/null

    # Extract from secret
    API_KEYS=$(kubectl get secret security-patch-agent-api-keys \
        -n security-patch-agent \
        -o jsonpath='{.data.api-keys}' 2>/dev/null | base64 -d)

    if [ -n "$API_KEYS" ]; then
        echo "✅ API Keys retrieved from Kubernetes secret:"
        echo ""

        # Split by comma and display
        IFS=',' read -ra KEYS <<< "$API_KEYS"
        for i in "${!KEYS[@]}"; do
            KEY="${KEYS[$i]}"
            echo "API_KEY_$((i+1)): $KEY"
        done

        echo ""
        echo "To test the API, run:"
        echo "  ./test-api.sh ${KEYS[0]}"
    else
        echo "❌ Could not retrieve API keys"
        echo ""
        echo "Manual steps:"
        echo "1. Go to: https://github.com/kannavkunal/security-patch-agent/settings/secrets/actions"
        echo "2. View API_KEY_PRIMARY value"
        echo "3. Run: ./test-api.sh YOUR_API_KEY"
    fi
fi
