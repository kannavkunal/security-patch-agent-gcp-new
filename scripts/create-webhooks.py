#!/usr/bin/env python3
"""
Create GitHub webhooks for all vulnerable test repositories

Prerequisites:
- GitHub Personal Access Token with 'admin:repo_hook' scope
- Export as: export GITHUB_TOKEN='your_token_here'

Usage:
    export GITHUB_TOKEN='ghp_...'
    python scripts/create-webhooks.py
"""

import os
import sys
from github import Github

# Configuration
WEBHOOK_URL = "http://34.67.157.196/webhook/github"
WEBHOOK_SECRET = "47dca8eeae767c5f07f4967864feadcdcb34688f41022c2c8e7402662e474cd3"

REPOSITORIES = [
    "kannavkunal/vulnerable-python-api",
    "kannavkunal/vulnerable-node-service",
    "kannavkunal/vulnerable-go-microservice",
    "kannavkunal/vulnerable-java-app",
]

def create_webhook(repo, webhook_url, secret):
    """Create a webhook for a repository"""
    try:
        # Check if webhook already exists
        existing_hooks = repo.get_hooks()
        for hook in existing_hooks:
            if hook.config.get('url') == webhook_url:
                print(f"  ⚠️  Webhook already exists for {repo.full_name}")
                print(f"     URL: {hook.config.get('url')}")
                print(f"     ID: {hook.id}")
                return hook

        # Create new webhook
        config = {
            "url": webhook_url,
            "content_type": "json",
            "secret": secret,
            "insecure_ssl": "0"  # Require SSL verification
        }

        events = ["pull_request"]  # Only trigger on PR events

        hook = repo.create_hook(
            name="web",
            config=config,
            events=events,
            active=True
        )

        print(f"  ✅ Created webhook for {repo.full_name}")
        print(f"     URL: {hook.config.get('url')}")
        print(f"     Events: {', '.join(hook.events)}")
        print(f"     ID: {hook.id}")
        return hook

    except Exception as e:
        print(f"  ❌ Failed to create webhook for {repo.full_name}: {e}")
        return None


def main():
    # Get GitHub token from environment
    token = os.getenv("GITHUB_TOKEN")
    if not token:
        print("❌ Error: GITHUB_TOKEN environment variable not set")
        print("")
        print("Please export your GitHub Personal Access Token:")
        print("  export GITHUB_TOKEN='ghp_...'")
        print("")
        print("The token needs 'admin:repo_hook' scope to create webhooks.")
        print("Create one at: https://github.com/settings/tokens")
        sys.exit(1)

    # Initialize GitHub client
    try:
        g = Github(token)
        user = g.get_user()
        print(f"📝 Authenticated as: {user.login}")
        print("")
    except Exception as e:
        print(f"❌ Failed to authenticate with GitHub: {e}")
        sys.exit(1)

    # Create webhooks for all repositories
    print(f"🔗 Creating webhooks for {len(REPOSITORIES)} repositories...")
    print(f"   Webhook URL: {WEBHOOK_URL}")
    print(f"   Events: pull_request")
    print("")

    success_count = 0
    for repo_name in REPOSITORIES:
        print(f"Processing: {repo_name}")
        try:
            repo = g.get_repo(repo_name)
            hook = create_webhook(repo, WEBHOOK_URL, WEBHOOK_SECRET)
            if hook:
                success_count += 1
        except Exception as e:
            print(f"  ❌ Failed to access repository {repo_name}: {e}")
        print("")

    # Summary
    print("=" * 60)
    print(f"✨ Summary:")
    print(f"   Total repositories: {len(REPOSITORIES)}")
    print(f"   Webhooks created/verified: {success_count}")
    print("")

    if success_count == len(REPOSITORIES):
        print("✅ All webhooks configured successfully!")
    else:
        print("⚠️  Some webhooks failed to configure. Check errors above.")

    print("")
    print("Next steps:")
    print("1. Test webhooks by creating a pull request")
    print("2. Check webhook deliveries at:")
    for repo_name in REPOSITORIES:
        print(f"   https://github.com/{repo_name}/settings/hooks")


if __name__ == "__main__":
    main()
