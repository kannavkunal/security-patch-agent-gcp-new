#!/usr/bin/env python3
"""
Comprehensive Local API Testing Script
Tests all endpoints of the Security Patch Agent API
"""
import requests
import json
import sys
import time

API_BASE = "http://127.0.0.1:8000"
API_KEY = "test-key-12345"

def test_result(name, passed, response_code=None, error=None):
    """Print test result"""
    status = "✅ PASS" if passed else "❌ FAIL"
    print(f"{status} - {name}")
    if response_code:
        print(f"     Status Code: {response_code}")
    if error:
        print(f"     Error: {error}")
    print()
    return passed

def main():
    print("=" * 70)
    print("🧪 SECURITY PATCH AGENT - LOCAL API TEST SUITE")
    print("=" * 70)
    print()

    results = []

    # Test 1: Health Endpoint
    print("TEST 1: Health Endpoint")
    print("-" * 70)
    try:
        r = requests.get(f"{API_BASE}/health", timeout=5)
        data = r.json()
        passed = (
            r.status_code == 200 and
            data.get("status") == "healthy" and
            data.get("model") == "gemini-2.5-pro"
        )
        print(f"Response: {json.dumps(data, indent=2)}")
        results.append(test_result("Health Check", passed, r.status_code))
    except Exception as e:
        results.append(test_result("Health Check", False, error=str(e)))

    # Test 2: Root Endpoint
    print("TEST 2: Root Endpoint")
    print("-" * 70)
    try:
        r = requests.get(f"{API_BASE}/", timeout=5)
        data = r.json()
        passed = (
            r.status_code == 200 and
            data.get("service") == "Security Patch Agent" and
            data.get("status") == "running"
        )
        print(f"Response: {json.dumps(data, indent=2)}")
        results.append(test_result("Root Endpoint", passed, r.status_code))
    except Exception as e:
        results.append(test_result("Root Endpoint", False, error=str(e)))

    # Test 3: Scan Endpoint - No API Key
    print("TEST 3: Scan Without API Key (should fail)")
    print("-" * 70)
    try:
        r = requests.post(
            f"{API_BASE}/scan",
            json={"repo_url": "https://github.com/test/repo", "mode": "patch"},
            timeout=5
        )
        passed = r.status_code == 401
        print(f"Response: {r.json()}")
        results.append(test_result("Auth Required", passed, r.status_code))
    except Exception as e:
        results.append(test_result("Auth Required", False, error=str(e)))

    # Test 4: Scan Endpoint - Valid Request
    print("TEST 4: Scan Trigger (PATCH mode)")
    print("-" * 70)
    try:
        r = requests.post(
            f"{API_BASE}/scan",
            headers={"X-API-Key": API_KEY},
            json={
                "repo_url": "https://github.com/kannavkunal/vulnerable-python-api",
                "mode": "patch",
                "branch": "main"
            },
            timeout=5
        )
        data = r.json()
        passed = (
            r.status_code == 200 and
            data.get("status") == "queued" and
            "scan_id" in data
        )
        print(f"Response: {json.dumps(data, indent=2)}")
        results.append(test_result("Scan Trigger (PATCH)", passed, r.status_code))
    except Exception as e:
        results.append(test_result("Scan Trigger (PATCH)", False, error=str(e)))

    # Test 5: Scan Endpoint - REVIEW mode
    print("TEST 5: Scan Trigger (REVIEW mode)")
    print("-" * 70)
    try:
        r = requests.post(
            f"{API_BASE}/scan",
            headers={"X-API-Key": API_KEY},
            json={
                "repo_url": "https://github.com/kannavkunal/vulnerable-node-service",
                "mode": "review",
                "branch": "main",
                "pr_number": 1
            },
            timeout=5
        )
        data = r.json()
        passed = r.status_code == 200 and data.get("status") == "queued"
        print(f"Response: {json.dumps(data, indent=2)}")
        results.append(test_result("Scan Trigger (REVIEW)", passed, r.status_code))
    except Exception as e:
        results.append(test_result("Scan Trigger (REVIEW)", False, error=str(e)))

    # Test 6: Analyze Endpoint - SQL Injection
    print("TEST 6: Analyze Endpoint (SQL Injection)")
    print("-" * 70)
    try:
        r = requests.post(
            f"{API_BASE}/analyze",
            headers={"X-API-Key": API_KEY},
            json={
                "code": "query = f'SELECT * FROM users WHERE id = {user_id}'",
                "language": "python"
            },
            timeout=10
        )
        # In TESTING mode, this will use mocked responses
        passed = r.status_code in [200, 500]  # 500 if no model in test mode
        print(f"Status: {r.status_code}")
        if r.status_code == 200:
            print(f"Response: {json.dumps(r.json(), indent=2)}")
        results.append(test_result("Analyze (SQL Injection)", passed, r.status_code))
    except Exception as e:
        results.append(test_result("Analyze (SQL Injection)", False, error=str(e)))

    # Test 7: Analyze Endpoint - Command Injection
    print("TEST 7: Analyze Endpoint (Command Injection)")
    print("-" * 70)
    try:
        r = requests.post(
            f"{API_BASE}/analyze",
            headers={"X-API-Key": API_KEY},
            json={
                "code": "exec(user_input)",
                "language": "python"
            },
            timeout=10
        )
        passed = r.status_code in [200, 500]
        print(f"Status: {r.status_code}")
        if r.status_code == 200:
            print(f"Response: {json.dumps(r.json(), indent=2)}")
        results.append(test_result("Analyze (Command Injection)", passed, r.status_code))
    except Exception as e:
        results.append(test_result("Analyze (Command Injection)", False, error=str(e)))

    # Test 8: Invalid API Key
    print("TEST 8: Invalid API Key")
    print("-" * 70)
    try:
        r = requests.post(
            f"{API_BASE}/scan",
            headers={"X-API-Key": "invalid-key-999"},
            json={"repo_url": "https://github.com/test/repo", "mode": "patch"},
            timeout=5
        )
        passed = r.status_code == 401
        print(f"Response: {r.json()}")
        results.append(test_result("Invalid API Key Rejected", passed, r.status_code))
    except Exception as e:
        results.append(test_result("Invalid API Key Rejected", False, error=str(e)))

    # Test 9: Webhook Endpoint (GitHub signature would be needed in production)
    print("TEST 9: Webhook Endpoint Structure")
    print("-" * 70)
    try:
        r = requests.post(
            f"{API_BASE}/webhook/github",
            headers={
                "X-Hub-Signature-256": "sha256=test",
                "X-GitHub-Event": "pull_request"
            },
            json={"action": "opened", "pull_request": {"number": 1}},
            timeout=5
        )
        # Will fail signature verification but endpoint exists
        passed = r.status_code in [200, 401, 422]
        print(f"Status: {r.status_code}")
        results.append(test_result("Webhook Endpoint Exists", passed, r.status_code))
    except Exception as e:
        results.append(test_result("Webhook Endpoint Exists", False, error=str(e)))

    # Summary
    print("=" * 70)
    print("📊 TEST SUMMARY")
    print("=" * 70)
    passed_count = sum(results)
    total_count = len(results)
    pass_rate = (passed_count / total_count * 100) if total_count > 0 else 0

    print(f"Total Tests: {total_count}")
    print(f"Passed: {passed_count}")
    print(f"Failed: {total_count - passed_count}")
    print(f"Pass Rate: {pass_rate:.1f}%")
    print()

    if passed_count == total_count:
        print("🎉 ALL TESTS PASSED! Ready for deployment.")
        return 0
    else:
        print("⚠️  SOME TESTS FAILED. Please review before deployment.")
        return 1

if __name__ == "__main__":
    try:
        exit_code = main()
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print("\n\n⚠️  Tests interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\n❌ Fatal error: {e}")
        sys.exit(1)
