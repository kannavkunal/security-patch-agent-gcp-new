#!/usr/bin/env python3
"""
Test PR Comment Formatting (No Network Required)
Shows what the PR comments will look like
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'app'))

from phases.p6_github import Phase6GitHub

def test_review_comment_format():
    """Test REVIEW mode comment formatting"""
    print("=" * 70)
    print("🧪 TEST: PR COMMENT FORMATTING (REVIEW MODE)")
    print("=" * 70)
    print()

    # Mock context
    context = {
        "scan_id": "test-scan-12345",
        "scan_mode": "review",
        "repo_url": "https://github.com/kannavkunal/vulnerable-python-api",
        "pr_number": 1,
        "vulnerabilities": [
            {
                "type": "SQL Injection",
                "severity": "CRITICAL",
                "file": "/tmp/repo/app.py",
                "line": 15,
                "description": "Unsafe SQL query construction using string formatting. This allows attackers to inject malicious SQL.",
                "code_snippet": "query = f'SELECT * FROM users WHERE id = {user_id}'"
            },
            {
                "type": "Command Injection",
                "severity": "HIGH",
                "file": "/tmp/repo/app.py",
                "line": 42,
                "description": "Direct execution of user input without validation",
                "code_snippet": "exec(user_input)"
            },
            {
                "type": "Hardcoded Secret",
                "severity": "HIGH",
                "file": "/tmp/repo/config.py",
                "line": 8,
                "description": "Database password exposed in source code",
                "code_snippet": "db_password = 'admin123'"
            },
            {
                "type": "Path Traversal",
                "severity": "MEDIUM",
                "file": "/tmp/repo/app.py",
                "line": 67,
                "description": "Unsanitized file path allows directory traversal",
                "code_snippet": "open(user_provided_path, 'r')"
            }
        ],
        "repo_path": "/tmp/repo"
    }

    # Create Phase6 instance
    phase6 = Phase6GitHub(context)

    # Generate comment
    comment = phase6._format_review_comment(context["vulnerabilities"])

    print("📝 GENERAL PR COMMENT:")
    print("=" * 70)
    print(comment)
    print("=" * 70)
    print()

    # Show inline comments
    print("📝 INLINE COMMENTS (first 3):")
    print("=" * 70)
    for i, vuln in enumerate(context["vulnerabilities"][:3], 1):
        path = vuln.get('file', '').replace(context.get('repo_path', ''), '').lstrip('/')
        inline = f"⚠️ **{vuln.get('type')}**\n\n{vuln.get('description', '')}"
        print(f"\n{i}. File: `{path}:{vuln.get('line')}`")
        print(f"   Comment:\n   {inline.replace(chr(10), chr(10) + '   ')}")
        print("-" * 70)

    print()
    return True

def test_pr_body_format():
    """Test PATCH mode PR body formatting"""
    print()
    print("=" * 70)
    print("🧪 TEST: PR BODY FORMATTING (PATCH MODE)")
    print("=" * 70)
    print()

    # Mock context
    context = {
        "scan_id": "test-scan-67890",
        "scan_mode": "patch",
        "vulnerabilities": [
            {
                "type": "SQL Injection",
                "severity": "CRITICAL",
                "file": "app.py",
                "line": 15
            },
            {
                "type": "Command Injection",
                "severity": "HIGH",
                "file": "app.py",
                "line": 42
            },
            {
                "type": "Hardcoded Secret",
                "severity": "HIGH",
                "file": "config.py",
                "line": 8
            }
        ],
        "patches": [
            {"file_path": "app.py"},
            {"file_path": "config.py"}
        ]
    }

    phase6 = Phase6GitHub(context)
    pr_body = phase6._format_pr_body(
        context["vulnerabilities"],
        context["patches"],
        context["scan_id"]
    )

    print("📝 PR TITLE:")
    print(f"🔒 Security Patches (scan-{context['scan_id']})")
    print()
    print("📝 PR BODY:")
    print("=" * 70)
    print(pr_body)
    print("=" * 70)
    print()

    return True

def main():
    print("=" * 70)
    print("🚀 PR COMMENT FORMATTING TESTS (LOCAL)")
    print("=" * 70)
    print()
    print("These tests show what comments will look like on GitHub")
    print("without actually creating them (no network required).")
    print()

    results = []
    results.append(("Review Comment Format", test_review_comment_format()))
    results.append(("PR Body Format", test_pr_body_format()))

    # Summary
    print("=" * 70)
    print("📊 TEST SUMMARY")
    print("=" * 70)
    for name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"{status} - {name}")
    print()

    if all(r[1] for r in results):
        print("🎉 ALL FORMATTING TESTS PASSED!")
        print()
        print("💡 These formats will be used when creating real comments")
        print("   in the deployed environment.")
        return 0
    else:
        print("⚠️  SOME TESTS FAILED")
        return 1

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
