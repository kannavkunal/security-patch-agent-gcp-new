# Repository Onboarding Guide

**How to add new GitHub repositories to the Security Patch Agent platform**

---

## 📋 Overview

This guide explains how to onboard a new GitHub repository to enable automated security scanning and patch generation.

**What you'll do:**
1. Add repository to the whitelist (code change)
2. Deploy updated configuration
3. Configure GitHub webhook on the new repository
4. Test the integration

**Time required:** ~10 minutes per repository

---

## 🔐 Prerequisites

- Repository must be accessible with your GitHub token
- You must have admin access to the repository
- Webhook secret already configured in GCP Secret Manager
- Security Patch Agent deployed and running

---

## Step 1: Add Repository to Whitelist

### 1.1 Edit the Worker Configuration

**File:** `app/worker.py`

Find the `ALLOWED_REPOS` list (around line 18):

```python
# Whitelist of allowed repositories (must match main.py)
ALLOWED_REPOS = [
    "https://github.com/kannavkunal/vulnerable-python-api",
    "https://github.com/kannavkunal/vulnerable-java-app",
    "https://github.com/kannavkunal/vulnerable-node-service",
    "https://github.com/kannavkunal/vulnerable-go-microservice",
]
```

**Add your new repository:**

```python
# Whitelist of allowed repositories (must match main.py)
ALLOWED_REPOS = [
    "https://github.com/kannavkunal/vulnerable-python-api",
    "https://github.com/kannavkunal/vulnerable-java-app",
    "https://github.com/kannavkunal/vulnerable-node-service",
    "https://github.com/kannavkunal/vulnerable-go-microservice",
    "https://github.com/YOUR_USERNAME/YOUR_NEW_REPO",  # ← Add here
]
```

### 1.2 Update Main API Configuration

**File:** `app/main.py`

Find the same `ALLOWED_REPOS` list (around line 70):

```python
# Repository whitelist
ALLOWED_REPOS = [
    "https://github.com/kannavkunal/vulnerable-python-api",
    "https://github.com/kannavkunal/vulnerable-java-app",
    "https://github.com/kannavkunal/vulnerable-node-service",
    "https://github.com/kannavkunal/vulnerable-go-microservice",
]
```

**Add the same repository:**

```python
# Repository whitelist
ALLOWED_REPOS = [
    "https://github.com/kannavkunal/vulnerable-python-api",
    "https://github.com/kannavkunal/vulnerable-java-app",
    "https://github.com/kannavkunal/vulnerable-node-service",
    "https://github.com/kannavkunal/vulnerable-go-microservice",
    "https://github.com/YOUR_USERNAME/YOUR_NEW_REPO",  # ← Add here
]
```

**⚠️ Important:** Both lists must match exactly!

---

## Step 2: Deploy Updated Configuration

### Option A: GitHub Actions (Recommended)

**2.1 Commit and Push Changes:**

```bash
git add app/worker.py app/main.py
git commit -m "Add YOUR_NEW_REPO to allowed repositories"
git push origin main
```

**2.2 Deploy via Workflow:**

1. Go to: https://github.com/YOUR_USERNAME/security-patch-agent-gcp/actions
2. Click **"Deploy Application"** workflow
3. Click **"Run workflow"**
4. Configure:
   - Environment: `production`
   - Deployment method: `kubernetes-manifests`
   - Components: `all`
5. Click **"Run workflow"**
6. Wait ~5 minutes for deployment

**2.3 Verify Deployment:**

```bash
# Check pods restarted
kubectl get pods -n security-patch-agent

# Check logs show new whitelist
kubectl logs -n security-patch-agent deployment/security-patch-agent -c api --tail=50 | grep "ALLOWED_REPOS"
```

---

### Option B: Manual Deployment

**2.1 Get GKE Credentials:**

```bash
gcloud container clusters get-credentials code-vulnerability-scanner \
  --region=us-central1 \
  --project=security-patch-agent-gcp
```

**2.2 Rebuild and Push Docker Image:**

```bash
cd app

# Build new image
docker build -t us-central1-docker.pkg.dev/security-patch-agent-gcp/security-patch-agent/api:latest .

# Configure Docker for GCP
gcloud auth configure-docker us-central1-docker.pkg.dev

# Push image
docker push us-central1-docker.pkg.dev/security-patch-agent-gcp/security-patch-agent/api:latest
```

**2.3 Restart Deployment:**

```bash
# Force rollout restart
kubectl rollout restart deployment/security-patch-agent -n security-patch-agent

# Wait for rollout
kubectl rollout status deployment/security-patch-agent -n security-patch-agent --timeout=5m
```

---

## Step 3: Configure GitHub Webhook

### 3.1 Get Required Information

**Get LoadBalancer IP:**

```bash
kubectl get svc security-patch-agent -n security-patch-agent
```

Copy the **EXTERNAL-IP** (e.g., `34.171.214.25`)

**Get Webhook Secret:**

```bash
# Retrieve from GCP Secret Manager
gcloud secrets versions access latest \
  --secret="github-webhook-secret" \
  --project=security-patch-agent-gcp
```

Copy this value - you'll need it next.

---

### 3.2 Add Webhook to GitHub Repository

**3.2.1 Navigate to Repository Settings:**

Go to: `https://github.com/YOUR_USERNAME/YOUR_NEW_REPO/settings/hooks`

**3.2.2 Click "Add webhook"**

**3.2.3 Configure Webhook:**

| Field | Value |
|-------|-------|
| **Payload URL** | `http://YOUR_LOADBALANCER_IP/webhook/github` |
| **Content type** | `application/json` |
| **Secret** | Paste the webhook secret from Step 3.1 |
| **SSL verification** | Enable SSL verification (if using HTTPS) |
| **Which events would you like to trigger this webhook?** | Select **"Let me select individual events"** |
| **Events** | ✅ Pull requests |
| **Active** | ✅ Check this box |

**3.2.4 Click "Add webhook"**

**3.2.5 Verify Webhook:**

- GitHub will send a test ping
- Check the webhook page - you should see a green ✓ for the ping event
- If red X, check:
  - LoadBalancer IP is correct
  - Webhook secret matches
  - Service is running

---

## Step 4: Test the Integration

### Test 1: PATCH Mode (Full Repository Scan)

**Trigger manual scan:**

```bash
# Get API key
API_KEY=$(kubectl get secret security-patch-agent-api-keys \
  -n security-patch-agent \
  -o jsonpath='{.data.api-keys}' | base64 -d | cut -d',' -f1)

# Get LoadBalancer IP
LB_IP=$(kubectl get svc security-patch-agent \
  -n security-patch-agent \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Trigger PATCH mode scan
curl -X POST http://$LB_IP/scan \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "repo_url": "https://github.com/YOUR_USERNAME/YOUR_NEW_REPO",
    "mode": "patch",
    "branch": "main"
  }'
```

**Expected response:**

```json
{
  "scan_id": "scan-abc123...",
  "status": "queued",
  "message": "Scan job created successfully"
}
```

**Monitor scan progress:**

```bash
# Watch Kubernetes jobs
kubectl get jobs -n security-patch-agent -w

# View scan logs
kubectl logs -n security-patch-agent job/<JOB_NAME> -f
```

**Check results:**

```bash
# BigQuery audit log
bq query --use_legacy_sql=false \
  "SELECT * FROM \`security-patch-agent-gcp.security_scans.scans\` 
   WHERE repo_name LIKE '%YOUR_NEW_REPO%' 
   ORDER BY timestamp DESC 
   LIMIT 1"

# Check for PR creation
# Go to: https://github.com/YOUR_USERNAME/YOUR_NEW_REPO/pulls
```

---

### Test 2: REVIEW Mode (PR Analysis)

**Create a test PR with a vulnerability:**

**Option 1: Add a simple SQL injection vulnerability**

```python
# Create file: vulnerable_endpoint.py
import sqlite3

def get_user(user_id):
    conn = sqlite3.connect('database.db')
    cursor = conn.cursor()
    
    # VULNERABLE: SQL Injection
    query = f"SELECT * FROM users WHERE id = {user_id}"
    cursor.execute(query)
    
    return cursor.fetchone()
```

**Option 2: Add a hardcoded secret**

```python
# Create file: config.py

# VULNERABLE: Hardcoded credentials
API_KEY = "sk-1234567890abcdef"
DATABASE_PASSWORD = "admin123"
AWS_SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

**Create and push the PR:**

```bash
# Create branch
git checkout -b test/add-vulnerability

# Add vulnerable file
git add vulnerable_endpoint.py  # or config.py
git commit -m "test: add vulnerable code for testing"

# Push branch
git push origin test/add-vulnerability

# Create PR via GitHub UI or CLI
gh pr create --title "Test: Vulnerability Detection" \
  --body "Testing Security Patch Agent integration"
```

**Expected behavior:**

1. GitHub sends webhook to your service (within seconds)
2. Service validates HMAC signature
3. REVIEW mode scan triggered automatically
4. Job created in Kubernetes
5. Scan analyzes PR diff only
6. PR comment added with vulnerability findings
7. Results logged to BigQuery

**Check webhook delivery:**

- Go to: `https://github.com/YOUR_USERNAME/YOUR_NEW_REPO/settings/hooks`
- Click your webhook
- Click **"Recent Deliveries"**
- You should see the PR event with a 200 response

**Check service logs:**

```bash
# Check API logs for webhook receipt
kubectl logs -n security-patch-agent deployment/security-patch-agent -c api --tail=100 | grep "webhook"

# Check worker logs for job processing
kubectl logs -n security-patch-agent deployment/security-patch-agent -c worker --tail=100
```

---

## 🎯 Complete Onboarding Checklist

Use this checklist for each new repository:

### Pre-Deployment
- [ ] Repository URL decided: `https://github.com/___/___`
- [ ] GitHub token has access to repository
- [ ] You have admin access to repository

### Code Changes
- [ ] Added repository to `app/worker.py` ALLOWED_REPOS
- [ ] Added repository to `app/main.py` ALLOWED_REPOS
- [ ] Both lists match exactly
- [ ] Changes committed and pushed to main

### Deployment
- [ ] Workflow deployed successfully (or manual deployment complete)
- [ ] Pods restarted with new configuration
- [ ] Verified whitelist updated in logs

### GitHub Webhook
- [ ] Got LoadBalancer IP: `___.___.___.__`
- [ ] Got webhook secret from Secret Manager
- [ ] Webhook configured in repository settings
- [ ] Webhook shows green ✓ for ping event

### Testing
- [ ] PATCH mode scan triggered successfully
- [ ] Scan completed without errors
- [ ] PR created with patches (if vulnerabilities found)
- [ ] BigQuery shows scan record
- [ ] Test PR created with vulnerability
- [ ] Webhook delivered successfully
- [ ] REVIEW mode scan triggered
- [ ] PR comment added with findings

---

## 📊 Monitoring Onboarded Repositories

### View All Scans by Repository

```bash
# BigQuery query
bq query --use_legacy_sql=false \
  "SELECT 
     repo_name,
     COUNT(*) as total_scans,
     SUM(vulnerabilities_found) as total_vulnerabilities,
     MAX(timestamp) as last_scan
   FROM \`security-patch-agent-gcp.security_scans.scans\`
   GROUP BY repo_name
   ORDER BY last_scan DESC"
```

### Check Repository Activity

```bash
# Get scan history for specific repo
bq query --use_legacy_sql=false \
  "SELECT scan_id, timestamp, scan_mode, status, vulnerabilities_found, pr_url
   FROM \`security-patch-agent-gcp.security_scans.scans\`
   WHERE repo_name = 'YOUR_NEW_REPO'
   ORDER BY timestamp DESC
   LIMIT 10"
```

### View Evidence Files

```bash
# List all evidence for a repository
gsutil ls gs://security-patch-evidence-security-patch-agent-gcp/YOUR_USERNAME/YOUR_NEW_REPO/
```

---

## 🔧 Troubleshooting

### Issue: "Repository not whitelisted" error

**Symptom:**
```json
{"detail": "Repository https://github.com/.../... is not in the allowed list"}
```

**Solution:**
1. Verify repository URL is **exactly** the same in both files
2. Check for trailing slashes or case differences
3. Redeploy application after changes

---

### Issue: Webhook shows red X or "delivery failed"

**Symptom:** GitHub webhook delivery fails with timeout or connection error

**Solutions:**

**Check LoadBalancer is accessible:**
```bash
LB_IP=$(kubectl get svc security-patch-agent -n security-patch-agent -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -v http://$LB_IP/health
```

**Check pods are running:**
```bash
kubectl get pods -n security-patch-agent
```

**Check webhook signature verification:**
```bash
# View API logs
kubectl logs -n security-patch-agent deployment/security-patch-agent -c api --tail=50
```

---

### Issue: Webhook delivers but scan doesn't start

**Symptom:** Webhook shows 200 OK but no job created

**Debug steps:**

1. **Check if webhook secret matches:**
```bash
# Compare values
gcloud secrets versions access latest --secret="github-webhook-secret"
# Should match the secret configured in GitHub webhook
```

2. **Check worker logs:**
```bash
kubectl logs -n security-patch-agent deployment/security-patch-agent -c worker --tail=100
```

3. **Check Pub/Sub:**
```bash
# Check if messages are queued
gcloud pubsub subscriptions describe security-scan-events-sub \
  --project=security-patch-agent-gcp
```

---

### Issue: Scan starts but fails

**Symptom:** Job created but exits with error

**Check job logs:**
```bash
# Get job name
kubectl get jobs -n security-patch-agent

# View logs
kubectl logs -n security-patch-agent job/JOB_NAME
```

**Common causes:**
- GitHub token doesn't have access to repository
- Repository is private and token lacks permissions
- Repository has no vulnerabilities (Phase 4 might fail)
- Network issues cloning repository

---

## 🔐 Security Best Practices

### Repository Access Control

**Principle of Least Privilege:**
- Only whitelist repositories you control or have permission to scan
- Review whitelist regularly
- Remove repositories that are no longer needed

### Token Scopes

**Ensure GitHub token has minimal required scopes:**
- ✅ `repo` (if repositories are private)
- ✅ `public_repo` (if repositories are public)
- ✅ `workflow` (to create PRs with patches)
- ❌ Avoid granting admin or delete permissions

### Webhook Security

**Validate all webhooks:**
- Always use HMAC signature verification
- Never disable `github-webhook-secret` validation
- Monitor failed webhook attempts
- Rotate webhook secret every 90 days

---

## 📈 Scaling Considerations

### Large Number of Repositories (10+)

**Consider these optimizations:**

1. **Use environment variable for whitelist:**
```python
# Instead of hardcoded list
import os
import json

ALLOWED_REPOS = json.loads(os.getenv("ALLOWED_REPOS", "[]"))
```

Store in ConfigMap:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: security-patch-agent-config
data:
  ALLOWED_REPOS: '["https://github.com/user/repo1", "https://github.com/user/repo2"]'
```

2. **Use wildcard patterns:**
```python
# Allow all repos from organization
def is_repo_allowed(repo_url):
    allowed_orgs = ["kannavkunal", "your-org"]
    for org in allowed_orgs:
        if repo_url.startswith(f"https://github.com/{org}/"):
            return True
    return False
```

3. **Database-backed whitelist:**
- Store allowed repositories in BigQuery
- Query on each request
- Update via API or console

---

## 🎓 Example: Onboarding a New Repository

**Scenario:** Add `https://github.com/mycompany/payment-service`

### Step-by-Step:

```bash
# 1. Edit worker.py
echo 'Add: "https://github.com/mycompany/payment-service"' >> app/worker.py

# 2. Edit main.py
echo 'Add: "https://github.com/mycompany/payment-service"' >> app/main.py

# 3. Commit and push
git add app/worker.py app/main.py
git commit -m "Add payment-service to allowed repositories"
git push origin main

# 4. Deploy
# (Run "Deploy Application" workflow on GitHub Actions)

# 5. Get webhook info
kubectl get svc security-patch-agent -n security-patch-agent
gcloud secrets versions access latest --secret="github-webhook-secret"

# 6. Configure webhook on GitHub
# (Manual step in GitHub UI)

# 7. Test PATCH mode
API_KEY=$(kubectl get secret security-patch-agent-api-keys -n security-patch-agent -o jsonpath='{.data.api-keys}' | base64 -d | cut -d',' -f1)
LB_IP=$(kubectl get svc security-patch-agent -n security-patch-agent -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -X POST http://$LB_IP/scan \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "repo_url": "https://github.com/mycompany/payment-service",
    "mode": "patch",
    "branch": "main"
  }'

# 8. Create test PR with vulnerability to test REVIEW mode
# (Manual step)

# Done! ✅
```

---

## 📞 Support

- **Questions:** Open an issue on GitHub
- **Email:** kannavkunal@gmail.com
- **Documentation:** See [README.md](README.md) and [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)

---

## ✅ Quick Reference

**Add Repository:**
1. Edit `app/worker.py` and `app/main.py`
2. Add URL to `ALLOWED_REPOS` in both files
3. Commit, push, deploy
4. Configure GitHub webhook
5. Test!

**Required Values:**
- LoadBalancer IP: `kubectl get svc -n security-patch-agent`
- Webhook Secret: `gcloud secrets versions access latest --secret=github-webhook-secret`
- API Key: `kubectl get secret security-patch-agent-api-keys -o jsonpath='{.data.api-keys}' | base64 -d`

**Test Commands:**
```bash
# PATCH mode
curl -X POST http://$LB_IP/scan -H "X-API-Key: $API_KEY" -d '{"repo_url":"...","mode":"patch"}'

# Check scans
bq query --use_legacy_sql=false "SELECT * FROM \`PROJECT.security_scans.scans\` ORDER BY timestamp DESC LIMIT 5"
```

---

**Ready to onboard your first repository?** Follow the steps above! 🚀
