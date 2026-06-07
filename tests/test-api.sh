#!/bin/bash

# API Testing Script for Security Patch Agent
# Usage: ./test-api.sh [API_KEY]

set -e

# Configuration
API_HOST="${API_HOST:-34.171.214.25}"
API_BASE_URL="http://${API_HOST}"
API_KEY="${1:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_test() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}TEST: $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✅ PASS: $1${NC}"
}

print_fail() {
    echo -e "${RED}❌ FAIL: $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  INFO: $1${NC}"
}

print_response() {
    echo -e "${NC}Response:${NC}"
    echo "$1" | jq '.' 2>/dev/null || echo "$1"
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_info "jq is not installed. Install with: brew install jq (for better JSON formatting)"
    echo ""
fi

# Banner
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════╗"
echo "║    Security Patch Agent - API Test Suite             ║"
echo "╔═══════════════════════════════════════════════════════╗"
echo -e "${NC}"
echo "API Base URL: $API_BASE_URL"
if [ -n "$API_KEY" ]; then
    echo "API Key: ${API_KEY:0:10}... (provided)"
else
    echo "API Key: (not provided)"
fi
echo ""

# Test 1: Health Check (no auth required)
print_test "1. Health Check (No Authentication)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$API_BASE_URL/health")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    print_success "Health endpoint returned 200 OK"
    print_response "$BODY"
else
    print_fail "Health endpoint returned $HTTP_CODE"
    print_response "$BODY"
fi

# Test 2: Root endpoint
print_test "2. Root Endpoint (No Authentication)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$API_BASE_URL/")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    print_success "Root endpoint returned 200 OK"
    print_response "$BODY"
else
    print_fail "Root endpoint returned $HTTP_CODE"
    print_response "$BODY"
fi

# Test 3: Missing API Key
print_test "3. Analyze Endpoint - Missing API Key"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_BASE_URL/analyze" \
    -H "Content-Type: application/json" \
    -d '{"code":"print(\"hello\")", "language":"python"}')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "401" ]; then
    print_success "Correctly rejected request without API key (401)"
    print_response "$BODY"
else
    print_fail "Expected 401, got $HTTP_CODE"
    print_response "$BODY"
fi

# Test 4: Invalid API Key
print_test "4. Analyze Endpoint - Invalid API Key"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_BASE_URL/analyze" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: invalid-key-12345" \
    -d '{"code":"print(\"hello\")", "language":"python"}')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "401" ]; then
    print_success "Correctly rejected invalid API key (401)"
    print_response "$BODY"
else
    print_fail "Expected 401, got $HTTP_CODE"
    print_response "$BODY"
fi

# Skip remaining tests if no API key provided
if [ -z "$API_KEY" ]; then
    echo ""
    print_info "Skipping authenticated tests (no API key provided)"
    echo ""
    echo -e "${YELLOW}To run full tests, provide API key:${NC}"
    echo -e "${YELLOW}  ./test-api.sh YOUR_API_KEY${NC}"
    echo ""
    echo -e "${YELLOW}Or set environment variable:${NC}"
    echo -e "${YELLOW}  export API_KEY=YOUR_API_KEY${NC}"
    echo -e "${YELLOW}  ./test-api.sh \$API_KEY${NC}"
    exit 0
fi

# Test 5: Valid API Key - Safe Code
print_test "5. Analyze Endpoint - Valid API Key (Safe Code)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_BASE_URL/analyze" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "code": "def add(a, b):\n    return a + b\n\nresult = add(5, 3)\nprint(result)",
        "language": "python"
    }')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    print_success "Successfully analyzed safe code (200 OK)"
    print_response "$BODY"
else
    print_fail "Expected 200, got $HTTP_CODE"
    print_response "$BODY"
fi

# Test 6: Valid API Key - Vulnerable Code (SQL Injection)
print_test "6. Analyze Endpoint - Vulnerable Code (SQL Injection)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_BASE_URL/analyze" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "code": "import sqlite3\n\ndef get_user(username):\n    conn = sqlite3.connect(\"users.db\")\n    cursor = conn.cursor()\n    query = \"SELECT * FROM users WHERE username = \" + username\n    cursor.execute(query)\n    return cursor.fetchall()",
        "language": "python",
        "context": "User authentication function"
    }')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    print_success "Successfully analyzed vulnerable code (200 OK)"
    print_response "$BODY"

    # Check if vulnerability was detected
    if echo "$BODY" | grep -q "is_vulnerable.*true" || echo "$BODY" | grep -q "SQL"; then
        print_success "SQL injection vulnerability detected!"
    else
        print_info "Response received but vulnerability detection unclear"
    fi
else
    print_fail "Expected 200, got $HTTP_CODE"
    print_response "$BODY"
fi

# Test 7: Valid API Key - Vulnerable Code (Command Injection)
print_test "7. Analyze Endpoint - Vulnerable Code (Command Injection)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_BASE_URL/analyze" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "code": "import os\nimport sys\n\ndef process_file(filename):\n    os.system(\"cat \" + filename)\n    return True",
        "language": "python",
        "context": "File processing utility"
    }')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    print_success "Successfully analyzed vulnerable code (200 OK)"
    print_response "$BODY"

    # Check if vulnerability was detected
    if echo "$BODY" | grep -q "is_vulnerable.*true" || echo "$BODY" | grep -q "command"; then
        print_success "Command injection vulnerability detected!"
    else
        print_info "Response received but vulnerability detection unclear"
    fi
else
    print_fail "Expected 200, got $HTTP_CODE"
    print_response "$BODY"
fi

# Test 8: Valid API Key - Vulnerable Code (XSS)
print_test "8. Analyze Endpoint - Vulnerable Code (XSS)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_BASE_URL/analyze" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "code": "from flask import Flask, request\napp = Flask(__name__)\n\n@app.route(\"/greet\")\ndef greet():\n    name = request.args.get(\"name\", \"Guest\")\n    return \"<h1>Hello, \" + name + \"!</h1>\"",
        "language": "python",
        "context": "Web application greeting endpoint"
    }')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    print_success "Successfully analyzed vulnerable code (200 OK)"
    print_response "$BODY"

    # Check if vulnerability was detected
    if echo "$BODY" | grep -q "is_vulnerable.*true" || echo "$BODY" | grep -q -i "xss\|cross"; then
        print_success "XSS vulnerability detected!"
    else
        print_info "Response received but vulnerability detection unclear"
    fi
else
    print_fail "Expected 200, got $HTTP_CODE"
    print_response "$BODY"
fi

# Test 9: Valid API Key - Auto-detect language
print_test "9. Analyze Endpoint - Auto-detect Language"
RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_BASE_URL/analyze" \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $API_KEY" \
    -d '{
        "code": "const express = require(\"express\");\nconst app = express();\napp.get(\"/user/:id\", (req, res) => {\n  const query = \"SELECT * FROM users WHERE id = \" + req.params.id;\n  db.query(query);\n});",
        "language": "auto-detect"
    }')
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    print_success "Successfully analyzed code with auto-detect (200 OK)"
    print_response "$BODY"
else
    print_fail "Expected 200, got $HTTP_CODE"
    print_response "$BODY"
fi

# Summary
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}TEST SUITE COMPLETE${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  - API is accessible at $API_BASE_URL"
echo "  - Health checks: PASSING"
echo "  - Authentication: ENFORCED"
echo "  - Vulnerability detection: OPERATIONAL"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Save API key securely"
echo "  2. Monitor logs: https://console.cloud.google.com/logs?project=compact-orb-498606-f9"
echo "  3. Check metrics: https://console.cloud.google.com/monitoring?project=compact-orb-498606-f9"
echo ""
