#!/usr/bin/env python3
"""
Test GitHub Integration Locally
Tests PR creation and commenting using real GitHub API
"""
import os
import sys
from google.cloud import secretmanager

# Set up environment
os.environ["GCP_PROJECT_ID"] = "compact-orb-498606-f9"
os.environ["GCP_LOCATION"] = "us-central1"

from app.clients.github_client import GitHubClient
from app.phases.p6_github import Phase6GitHub

def test_pr_comments():
    """Test creating comments on an existing PR"""
    print("=" * 70)
    print("🧪 TEST: GitHub PR Comments (REVIEW Mode)")
    print("=" * 70)
    print()

    # Create mock context for review mode
    context = {
        "scan_id": "test-local-scan-001",
        "scan_mode": "review",
        "repo_url": "https://github.com/kannavkunal/vulnerable-python-api",
        "pr_number": 1,  # Assuming PR #1 exists
        "vulnerabilities": [
            {
                "type": "SQL Injection",
                "severity": "CRITICAL",
                "file": "app.py",
                "line": 15,
                "description": "Unsafe SQL query construction using string formatting",
                "code_snippet": "query = f'SELECT * FROM users WHERE id = {user_id}'"
            },
            {
                "type": "Command Injection",
                "severity": "HIGH",
                "file": "app.py",
                "line": 42,
                "description": "Direct execution of user input",
                "code_snippet": "exec(user_input)"
            },
            {
                "type": "Hardcoded Secret",
                "severity": "HIGH",
                "file": "app.py",
                "line": 8,
                "description": "Database password hardcoded in source",
                "code_snippet": "db_password = 'admin123'"
            }
        ],
        "repo_path": "/tmp/test"
    }

    print("📝 Test Configuration:")
    print(f"  Repository: {context['repo_url']}")
    print(f"  PR Number: #{context['pr_number']}")
    print(f"  Vulnerabilities: {len(context['vulnerabilities'])}")
    print()

    # Check if PR exists first
    print("1️⃣ Checking if PR #1 exists...")
    try:
        client = GitHubClient()
        parts = context['repo_url'].replace("https://github.com/", "").split("/")
        owner, repo_name = parts[0], parts[1]
        repo = client.client.get_repo(f"{owner}/{repo_name}")

        try:
            pr = repo.get_pull(context['pr_number'])
            print(f"   ✅ PR #{pr.number} found: {pr.title}")
            print(f"   State: {pr.state}")
            print(f"   URL: {pr.html_url}")
        except Exception as e:
            print(f"   ❌ PR #1 not found. Creating a test PR first...")
            print(f"   Error: {e}")
            return False
    except Exception as e:
        print(f"   ❌ Error accessing GitHub: {e}")
        return False

    print()
    print("2️⃣ Creating security review comments...")
    try:
        # Initialize Phase 6 with context
        phase6 = Phase6GitHub(context)
        result = phase6._add_pr_comments()

        print(f"   ✅ Comments added successfully!")
        print(f"   Comments created: {result.get('comments_added', 0)}")
        print()
        print(f"🔗 View comments at: {pr.html_url}")
        return True

    except Exception as e:
        print(f"   ❌ Error creating comments: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_pr_creation():
    """Test creating a new PR with patches"""
    print()
    print("=" * 70)
    print("🧪 TEST: GitHub PR Creation (PATCH Mode)")
    print("=" * 70)
    print()

    # Create mock context for patch mode
    context = {
        "scan_id": "test-local-scan-002",
        "scan_mode": "patch",
        "repo_url": "https://github.com/kannavkunal/vulnerable-python-api",
        "vulnerabilities": [
            {
                "type": "SQL Injection",
                "severity": "CRITICAL",
                "file": "app.py",
                "line": 15,
                "description": "Unsafe SQL query construction"
            }
        ],
        "patches": [
            {
                "file_path": "app.py",
                "vulnerability_type": "SQL Injection",
                "patched_code": """from flask import Flask
import sqlite3

app = Flask(__name__)

# FIXED: Use parameterized query
def get_user(user_id):
    conn = sqlite3.connect('database.db')
    cursor = conn.cursor()
    cursor.execute('SELECT * FROM users WHERE id = ?', (user_id,))
    return cursor.fetchone()
""",
                "original_code": "query = f'SELECT * FROM users WHERE id = {user_id}'"
            }
        ],
        "repo_path": "/tmp/test"
    }

    print("📝 Test Configuration:")
    print(f"  Repository: {context['repo_url']}")
    print(f"  Patches: {len(context['patches'])}")
    print(f"  Files to update: {[p['file_path'] for p in context['patches']]}")
    print()

    print("⚠️  WARNING: This will create a REAL PR on GitHub!")
    print("   Press Enter to continue or Ctrl+C to cancel...")
    try:
        input()
    except KeyboardInterrupt:
        print("\n   Cancelled by user")
        return False

    print()
    print("1️⃣ Creating new branch and PR with security patches...")
    try:
        phase6 = Phase6GitHub(context)
        result = phase6._create_pr()

        print(f"   ✅ PR created successfully!")
        print(f"   PR Number: #{result.get('pr_number')}")
        print(f"   PR URL: {result.get('pr_url')}")
        print()
        print(f"🔗 View PR at: {result.get('pr_url')}")
        return True

    except Exception as e:
        print(f"   ❌ Error creating PR: {e}")
        import traceback
        traceback.print_exc()
        return False

def check_pr_exists():
    """Check if we have a test PR to work with"""
    print("=" * 70)
    print("🔍 CHECKING TEST ENVIRONMENT")
    print("=" * 70)
    print()

    print("1️⃣ Checking GitHub access...")
    try:
        client = GitHubClient()
        user = client.client.get_user()
        print(f"   ✅ Authenticated as: {user.login}")
        print(f"   Name: {user.name}")
    except Exception as e:
        print(f"   ❌ GitHub authentication failed: {e}")
        return False

    print()
    print("2️⃣ Checking repository access...")
    try:
        repo = client.client.get_repo("kannavkunal/vulnerable-python-api")
        print(f"   ✅ Repository: {repo.full_name}")
        print(f"   Default branch: {repo.default_branch}")
        print(f"   Has push access: {repo.permissions.push}")
    except Exception as e:
        print(f"   ❌ Cannot access repository: {e}")
        return False

    print()
    print("3️⃣ Checking for test PRs...")
    try:
        pulls = list(repo.get_pulls(state='all', sort='created', direction='desc'))[:5]
        if pulls:
            print(f"   ✅ Found {len(pulls)} recent PRs:")
            for pr in pulls:
                print(f"      #{pr.number}: {pr.title} ({pr.state})")
        else:
            print(f"   ⚠️  No PRs found - will need to create one for testing")
    except Exception as e:
        print(f"   ❌ Error listing PRs: {e}")
        return False

    print()
    return True

def main():
    print("=" * 70)
    print("🚀 GITHUB INTEGRATION - LOCAL TESTING")
    print("=" * 70)
    print()

    # Check environment
    if not check_pr_exists():
        print("\n❌ Environment check failed. Cannot proceed with tests.")
        return 1

    print("\n" + "=" * 70)
    print("📋 TEST OPTIONS")
    print("=" * 70)
    print("1. Test PR Comments (REVIEW mode) - Add security review to existing PR")
    print("2. Test PR Creation (PATCH mode) - Create new PR with fixes")
    print("3. Both tests")
    print("4. Exit")
    print()

    choice = input("Select test (1-4): ").strip()

    results = []

    if choice in ['1', '3']:
        results.append(("PR Comments", test_pr_comments()))

    if choice in ['2', '3']:
        results.append(("PR Creation", test_pr_creation()))

    if choice == '4' or not results:
        print("\nExiting...")
        return 0

    # Summary
    print()
    print("=" * 70)
    print("📊 TEST SUMMARY")
    print("=" * 70)
    for name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"{status} - {name}")
    print()

    all_passed = all(r[1] for r in results)
    if all_passed:
        print("🎉 ALL TESTS PASSED!")
        return 0
    else:
        print("⚠️  SOME TESTS FAILED")
        return 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\n⚠️  Tests interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
