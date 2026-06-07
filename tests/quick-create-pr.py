#!/usr/bin/env python3
"""Quick script to create test PR for REVIEW mode testing"""
import os
import sys
import requests
import json

# Get token
token = os.popen("gcloud secrets versions access latest --secret=github-token 2>/dev/null").read().strip()

if not token:
    print("❌ Failed to get GitHub token")
    sys.exit(1)

# Create PR via API
url = "https://api.github.com/repos/kannavkunal/vulnerable-node-service/pulls"
headers = {
    "Authorization": f"token {token}",
    "Accept": "application/vnd.github.v3+json"
}
data = {
    "title": "Test PR for Security Review",
    "body": "This PR is for testing the automated security review system. The webhook should trigger and add security comments.",
    "head": "test/security-review-1780782603",
    "base": "main"
}

try:
    r = requests.post(url, headers=headers, json=data)
    if r.status_code == 201:
        pr = r.json()
        print(f"✅ PR Created: #{pr['number']}")
        print(f"🔗 URL: {pr['html_url']}")
    else:
        print(f"❌ Error {r.status_code}: {r.json().get('message', r.text)}")
        sys.exit(1)
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
