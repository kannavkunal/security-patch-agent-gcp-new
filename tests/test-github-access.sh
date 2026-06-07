#!/bin/bash
# Test if pods can access GitHub token and clone repos

set -e

# Read from environment variables (required)
PROJECT_ID="${GCP_PROJECT_ID}"

# Validate required variables
if [ -z "$PROJECT_ID" ]; then
    echo ""
    echo "ERROR: GCP_PROJECT_ID environment variable is not set"
    echo ""
    echo "Usage:"
    echo "  export GCP_PROJECT_ID='your-project-id'"
    echo "  ./test-github-access.sh"
    echo ""
    exit 1
fi

echo "🧪 Testing GitHub Access from Kubernetes Pod"
echo "=============================================="
echo ""
echo "Project ID: $PROJECT_ID"
echo ""

# Get cluster credentials
echo "1️⃣ Getting GKE credentials..."
gcloud container clusters get-credentials code-vulnerability-scanner \
  --region=us-central1 \
  --project=$PROJECT_ID

# Check if pods are running
echo ""
echo "2️⃣ Checking if pods are running..."
kubectl get pods -n security-patch-agent --insecure-skip-tls-verify

# Get first running pod
POD_NAME=$(kubectl get pods -n security-patch-agent --insecure-skip-tls-verify -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
  echo "❌ No pods found in security-patch-agent namespace"
  echo "   Run the deployment workflow first!"
  exit 1
fi

echo "   Using pod: $POD_NAME"

# Test 1: Check if pod can access Secret Manager
echo ""
echo "3️⃣ Test: Can pod read GitHub token from Secret Manager?"
kubectl exec -n security-patch-agent $POD_NAME -c api --insecure-skip-tls-verify -- python3 -c "
from google.cloud import secretmanager
client = secretmanager.SecretManagerServiceClient()
secret_name = 'projects/$PROJECT_ID/secrets/github-token/versions/latest'
try:
    response = client.access_secret_version(request={'name': secret_name})
    token = response.payload.data.decode('UTF-8')
    print('✅ SUCCESS: Token retrieved (length: {} chars)'.format(len(token)))
    print('   Token starts with: {}...'.format(token[:7]))
except Exception as e:
    print('❌ FAILED: {}'.format(e))
" || echo "❌ Failed to access secret"

# Test 2: Check if git is installed
echo ""
echo "4️⃣ Test: Is git installed in container?"
kubectl exec -n security-patch-agent $POD_NAME -c api --insecure-skip-tls-verify -- which git || echo "⚠️  git not found (might be in api container but not worker)"

# Test 3: Try to clone a public repo (no auth needed)
echo ""
echo "5️⃣ Test: Can pod clone a public GitHub repo?"
kubectl exec -n security-patch-agent $POD_NAME -c api --insecure-skip-tls-verify -- bash -c "
cd /tmp
rm -rf test-clone 2>/dev/null || true
git clone --depth 1 https://github.com/kannavkunal/vulnerable-python-api.git test-clone 2>&1 | head -10
if [ -d test-clone ]; then
  echo '✅ SUCCESS: Cloned public repo'
  ls -la test-clone | head -5
  rm -rf test-clone
else
  echo '❌ FAILED: Could not clone public repo'
fi
" || echo "❌ Clone failed"

# Test 4: Try to clone using the token (for private repos)
echo ""
echo "6️⃣ Test: Can pod clone using GitHub token?"
kubectl exec -n security-patch-agent $POD_NAME -c api --insecure-skip-tls-verify -- python3 -c "
import os
import subprocess
from google.cloud import secretmanager

# Get token
client = secretmanager.SecretManagerServiceClient()
secret_name = 'projects/$PROJECT_ID/secrets/github-token/versions/latest'
response = client.access_secret_version(request={'name': secret_name})
token = response.payload.data.decode('UTF-8').strip()

# Try to clone using token
repo_url = 'https://github.com/kannavkunal/vulnerable-python-api.git'
auth_url = f'https://{token}@github.com/kannavkunal/vulnerable-python-api.git'

try:
    os.chdir('/tmp')
    subprocess.run(['rm', '-rf', 'test-clone-auth'], check=False)
    result = subprocess.run(
        ['git', 'clone', '--depth', '1', auth_url, 'test-clone-auth'],
        capture_output=True,
        text=True,
        timeout=30
    )
    if result.returncode == 0:
        print('✅ SUCCESS: Cloned using token authentication')
        subprocess.run(['ls', '-la', 'test-clone-auth'])
        subprocess.run(['rm', '-rf', 'test-clone-auth'])
    else:
        print('❌ FAILED: Clone with token failed')
        print('STDERR:', result.stderr[:200])
except Exception as e:
    print('❌ FAILED:', e)
" || echo "❌ Token-based clone failed"

# Test 5: Check PyGithub functionality
echo ""
echo "7️⃣ Test: Can PyGithub library authenticate?"
kubectl exec -n security-patch-agent $POD_NAME -c api --insecure-skip-tls-verify -- python3 -c "
from google.cloud import secretmanager
from github import Github

# Get token
client = secretmanager.SecretManagerServiceClient()
secret_name = 'projects/$PROJECT_ID/secrets/github-token/versions/latest'
response = client.access_secret_version(request={'name': secret_name})
token = response.payload.data.decode('UTF-8').strip()

# Test PyGithub
try:
    g = Github(token)
    user = g.get_user()
    print(f'✅ SUCCESS: Authenticated as {user.login}')
    print(f'   Name: {user.name}')
    print(f'   Email: {user.email}')

    # Try to get a repo
    repo = g.get_repo('kannavkunal/vulnerable-python-api')
    print(f'   Can access repo: {repo.full_name}')
    print(f'   Default branch: {repo.default_branch}')
except Exception as e:
    print(f'❌ FAILED: {e}')
" || echo "❌ PyGithub test failed"

echo ""
echo "=============================================="
echo "✅ Testing complete!"
echo ""
echo "📝 Summary:"
echo "  - Secret Manager access: Check output above"
echo "  - Git clone (public): Check output above"
echo "  - Git clone (with token): Check output above"
echo "  - PyGithub authentication: Check output above"
echo ""
echo "If all tests pass, your pods can clone GitHub repos! 🎉"
