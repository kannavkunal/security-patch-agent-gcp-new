#!/usr/bin/env python3
"""
Test script to verify GitHub token can be retrieved from Secret Manager
"""
from google.cloud import secretmanager

def get_secret(secret_id: str, project_id: str = "compact-orb-498606-f9") -> str:
    """Retrieve secret from Secret Manager"""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"

    try:
        response = client.access_secret_version(request={"name": name})
        secret_value = response.payload.data.decode('UTF-8')
        return secret_value
    except Exception as e:
        print(f"❌ Failed to retrieve secret: {e}")
        return None

if __name__ == "__main__":
    print("Testing Secret Manager access...")

    # Test GitHub token
    token = get_secret("github-token")
    if token:
        # Mask the token for security
        masked = f"{token[:7]}...{token[-4:]}" if len(token) > 11 else "***"
        print(f"✅ GitHub token retrieved: {masked}")
        print(f"   Length: {len(token)} characters")
    else:
        print("❌ Could not retrieve GitHub token")
        print("\nTroubleshooting:")
        print("1. Have you run 'terraform apply'?")
        print("2. Have you added the token with 'gcloud secrets versions add'?")
        print("3. Does your service account have secretmanager.secretAccessor role?")
