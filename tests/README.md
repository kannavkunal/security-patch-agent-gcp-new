# Test Scripts

This directory contains various test scripts for the Security Patch Agent.

## Test Scripts

### API Testing
- **test-api.sh** - Comprehensive API endpoint testing
- **test-local-apis.py** - Local API testing (Python)
- **test_deployment.sh** - Deployment verification tests

### GitHub Integration Testing
- **test-github-access.sh** - GitHub API access verification
- **test-github-integration.py** - Full GitHub integration tests
- **test-github-simple.py** - Simple GitHub connectivity test
- **test-pr-comment-format.py** - PR comment formatting tests

### Utility Scripts
- **test-secret-access.py** - Secret Manager access verification
- **quick-create-pr.py** - Quick PR creation for testing

## Main Test Suites (in root directory)

For end-to-end testing, use these scripts from the repository root:

```bash
# Quick validation test
./quick_test.sh

# Comprehensive E2E test (PATCH mode, GET endpoints, BigQuery, GCS)
./test_e2e_complete.sh

# REVIEW mode test (PR security scanning)
./test_review_mode.sh
```

## Running Tests

### Prerequisites

Ensure you have:
- GKE cluster running with Security Patch Agent deployed
- API endpoint accessible
- GitHub token configured
- GCP credentials set up

### Example Usage

```bash
# Test API endpoints
cd tests/
./test-api.sh

# Test GitHub integration
./test-github-integration.py

# Verify deployment
./test_deployment.sh
```

## Test Environment Variables

Some tests require environment variables:

```bash
export API_URL="http://YOUR_LOAD_BALANCER_IP"
export GITHUB_TOKEN="ghp_YOUR_TOKEN"
export GCP_PROJECT_ID="your-project-id"
```

See **TESTING_GUIDE.md** in the root directory for comprehensive testing procedures.
