# Security Patch Agent - Installation Guide

> **Deploy to GCP in 20 minutes using GitHub Actions automation**

---

## Installation Flow

```
Prerequisites (15 min) → Run GitHub Actions Pipeline (10 min) → Testing (5 min)
```

---

## Part 1: Prerequisites (Manual Setup)

### 1.1 Install Tools

```bash
# macOS
brew install google-cloud-sdk kubectl terraform git

# Verify
gcloud --version
kubectl version --client  
terraform --version
```

### 1.2 Create GCP Project

```bash
export PROJECT_ID="security-patch-agent-gcp"

# Create project
gcloud projects create $PROJECT_ID --name="Security Patch Agent"
gcloud config set project $PROJECT_ID
```

### 1.3 Enable Required APIs

```bash
gcloud services enable \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  pubsub.googleapis.com \
  bigquery.googleapis.com \
  storage.googleapis.com \
  secretmanager.googleapis.com \
  aiplatform.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  compute.googleapis.com
```

**Time:** 1-2 minutes

### 1.4 Authenticate

**Personal Account:**
```bash
gcloud auth login
gcloud auth application-default login
```

**Service Account (for CI/CD):**
```bash
gcloud auth activate-service-account \
  --key-file=/path/to/key.json
  
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
```

### 1.5 Create Secret Manager Secrets

**Only 2 secrets needed** (Vertex AI uses Workload Identity):

**GitHub Token:**
1. Go to: https://github.com/settings/tokens
2. Generate token (classic), scope: `repo`
3. Save token

```bash
echo -n "ghp_YOUR_TOKEN" | gcloud secrets create github-token \
  --project=$PROJECT_ID \
  --data-file=- \
  --replication-policy="automatic"
```

**Webhook Secret:**
```bash
WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "Save this: $WEBHOOK_SECRET"  # For GitHub webhook config later

echo -n "$WEBHOOK_SECRET" | gcloud secrets create github-webhook-secret \
  --project=$PROJECT_ID \
  --data-file=- \
  --replication-policy="automatic"

# Verify
gcloud secrets list --project=$PROJECT_ID
```

### 1.6 Create Terraform State Bucket

```bash
# Required before running pipeline
gsutil mb -p $PROJECT_ID \
  -c STANDARD \
  -l us-central1 \
  gs://${PROJECT_ID}-terraform-state

gsutil versioning set on gs://${PROJECT_ID}-terraform-state
```

### 1.7 Set GitHub Repository Secrets

Go to: **Your Fork** → **Settings** → **Secrets and variables** → **Actions**

Add these 4 secrets:

| Secret Name | Value | How to Get |
|-------------|-------|------------|
| `GCP_PROJECT_ID` | `security-patch-agent-gcp` | Your project ID |
| `GCP_SERVICE_ACCOUNT_KEY` | `{...JSON...}` | Download from IAM → Service Accounts → Keys |
| `API_KEY_PRIMARY` | `<hex string>` | `openssl rand -hex 32` |
| `API_KEY_SECONDARY` | `<hex string>` | `openssl rand -hex 32` |

---

## Part 2: Run GitHub Actions Pipeline

### 2.1 Trigger Deployment

1. Go to your forked repository
2. Click: **Actions** tab
3. Select: **"Full Deployment"** workflow
4. Click: **"Run workflow"**
5. Configure options:
   ```
   ☑ Deploy infrastructure (Terraform)
   ☑ Build and push Docker images
   ☑ Deploy application to GKE
   ```
6. Click: **"Run workflow"**

### 2.2 Monitor Pipeline

Watch the workflow run in GitHub Actions.

**What it does:**
1. **Terraform** (8 min)
   - Creates GKE cluster
   - Creates Pub/Sub topic + subscription + DLQ
   - Creates BigQuery dataset + tables
   - Creates GCS evidence bucket
   - Configures IAM + Workload Identity
   - Sets up monitoring dashboards

2. **Build & Push** (3 min)
   - Builds Docker image
   - Pushes to Artifact Registry

3. **Deploy** (2 min)
   - Deploys K8s manifests
   - Creates ConfigMap (repositories)
   - Creates Secret (API keys)
   - Waits for pod readiness

**Total time:** ~15 minutes

---

## Part 3: Customize for Your Organization

**IMPORTANT:** The default deployment scans demo repositories. Update these for your team's repos.

### 3.1 Update Repository Whitelist

The system uses a ConfigMap to control which repositories can be scanned (security control).

**Default repositories (demo only):**
```yaml
VULNERABLE_REPOS: |
  https://github.com/kannavkunal/vulnerable-python-api
  https://github.com/kannavkunal/vulnerable-node-service
  https://github.com/kannavkunal/vulnerable-go-microservice
  https://github.com/kannavkunal/vulnerable-java-app
```

**Update for your team:**

**Option A: Via GitHub Actions (Recommended)**

1. Edit `.github/workflows/deploy-application.yml`
2. Find the ConfigMap creation step (around line 175)
3. Update `VULNERABLE_REPOS` with your repositories:

```yaml
--from-literal=VULNERABLE_REPOS="https://github.com/YOUR-ORG/repo1,https://github.com/YOUR-ORG/repo2,https://github.com/YOUR-ORG/repo3"
```

4. Commit and re-run the workflow

**Option B: Via kubectl (Quick update)**

```bash
# Update ConfigMap directly
kubectl create configmap security-patch-agent-config \
  --from-literal=VULNERABLE_REPOS="https://github.com/YOUR-ORG/repo1,https://github.com/YOUR-ORG/repo2,https://github.com/YOUR-ORG/repo3" \
  --from-literal=GCP_PROJECT_ID="$PROJECT_ID" \
  -n security-patch-agent \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new config
kubectl rollout restart deployment/security-patch-agent -n security-patch-agent

# Verify new config
kubectl get configmap security-patch-agent-config -n security-patch-agent -o yaml
```

**Important notes:**
- ✅ Only whitelisted repositories can be scanned (security feature)
- ✅ Use comma-separated list (no spaces after commas)
- ✅ Full URLs required (e.g., `https://github.com/org/repo`)
- ❌ Private repos work (uses GitHub token from Secret Manager)

### 3.2 Update API Keys (Optional)

If you want to rotate API keys:

```bash
# Generate new keys
NEW_KEY_1=$(openssl rand -hex 32)
NEW_KEY_2=$(openssl rand -hex 32)

# Update secret
kubectl create secret generic security-patch-agent-api-keys \
  --from-literal=api-keys="$NEW_KEY_1,$NEW_KEY_2" \
  -n security-patch-agent \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart to pick up new keys
kubectl rollout restart deployment/security-patch-agent -n security-patch-agent
```

### 3.3 Update GitHub Token (If Expired)

GitHub tokens expire after 90 days. To update:

```bash
# Create new token at https://github.com/settings/tokens
# Then update Secret Manager:

echo -n "ghp_NEW_TOKEN" | gcloud secrets versions add github-token \
  --project=$PROJECT_ID \
  --data-file=-

# Restart pods
kubectl rollout restart deployment/security-patch-agent -n security-patch-agent
```

### 3.4 Common Customizations Per Team

| What to Change | Where | Why |
|----------------|-------|-----|
| **Repository list** | ConfigMap `VULNERABLE_REPOS` | Add your team's repos |
| **API keys** | K8s Secret `security-patch-agent-api-keys` | Team-specific auth |
| **GitHub token** | Secret Manager `github-token` | Use your org's token |
| **Webhook secret** | Secret Manager `github-webhook-secret` | Team-specific HMAC |
| **Scan frequency** | Webhook config | Per-PR vs manual |

---

## Part 4: Testing & Verification

### 4.1 Get Cluster Credentials

```bash
gcloud container clusters get-credentials code-vulnerability-scanner \
  --region=us-central1 \
  --project=$PROJECT_ID
```

### 4.2 Check Deployment Status

```bash
# Check pods (should show 2/2 Running)
kubectl get pods -n security-patch-agent

# Expected:
NAME                                   READY   STATUS    RESTARTS   AGE
security-patch-agent-8c8547d8f-xxxxx   2/2     Running   0          5m
```

### 4.3 Get External IP

```bash
kubectl get svc security-patch-agent -n security-patch-agent

# Copy EXTERNAL-IP (may take 2-3 min to provision)
export API_IP=<EXTERNAL_IP>
```

### 4.4 Test API

```bash
# Health check
curl http://$API_IP/health
# Expected: {"status":"healthy"}

# List repositories
curl http://$API_IP/repositories
# Expected: {"count":4,"repositories":[...]}
```

### 4.5 Open Web UI

```
http://<EXTERNAL_IP>/
```

**You should see:** Security Patch Agent web interface

### 4.6 Test PATCH Mode (Manual Scan)

**Via Web UI:**
1. Enter API key (from GitHub secret)
2. Select repository from dropdown
3. Select mode: **PATCH**
4. Click **"Start Scan"**

**Via API:**
```bash
# Get API key
API_KEY=$(kubectl get secret security-patch-agent-api-keys \
  -n security-patch-agent \
  -o jsonpath='{.data.api-keys}' | base64 -d | cut -d',' -f1)

# Trigger scan
curl -X POST http://$API_IP/scan \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "repo_url": "https://github.com/YOUR-ORG/vulnerable-repo",
    "mode": "patch",
    "branch": "main"
  }'

# Response: {"scan_id":"scan-...","status":"queued"}
```

**Monitor scan:**
```bash
# Watch worker process message
kubectl logs -n security-patch-agent -l app=security-patch-agent -c worker -f

# Watch scan job
kubectl get jobs -n security-patch-agent --watch
```

**Expected flow:**
```
1. API receives request → publishes to Pub/Sub
2. Worker picks up message → creates K8s Job
3. Job executes 8 phases:
   - Phase 1: Analyzes repository (language detection)
   - Phase 2: Detects vulnerabilities (Semgrep/Bandit)
   - Phase 3: Plans remediation (Gemini with past context)
   - Phase 4: Generates patches (Gemini)
   - Phase 5: Verification (stub)
   - Phase 6: Creates GitHub PR with fixes
   - Phase 7: Logs to BigQuery
   - Phase 8: Generates security evidence
4. PR appears on GitHub with fixes
5. Scan results in BigQuery
```

### 4.7 Test REVIEW Mode (Webhook on PR)

**Configure webhook:**

1. Go to: `https://github.com/YOUR-ORG/YOUR-REPO/settings/hooks`
2. Click: **"Add webhook"**
3. Configure:
   - **Payload URL:** `http://<EXTERNAL_IP>/webhook/github`
   - **Content type:** `application/json`
   - **Secret:** `<WEBHOOK_SECRET from step 1.5>`
   - **Events:** ☑ Pull requests only
   - ☑ Active
4. **Add webhook**

**Test webhook:**
```bash
# Create test PR
cd your-repo
git checkout -b test-webhook
echo "test" >> README.md
git commit -am "test webhook"
git push origin test-webhook
# Create PR via GitHub UI
```

**Expected:**
- Webhook triggers scan in REVIEW mode
- Bot posts security comment on PR
- Worker logs show: `Webhook: Queueing review scan for <repo> PR#<num>`

### 4.8 Verify BigQuery Logs

```bash
# View recent scans
bq query --project_id=$PROJECT_ID --use_legacy_sql=false \
  "SELECT scan_id, repo_name, scan_mode, status, vulnerabilities_found, pr_number 
   FROM security_scans.scans 
   ORDER BY timestamp DESC 
   LIMIT 5"
```

### 4.9 Access Cloud Console

**GKE Workloads:**
```
https://console.cloud.google.com/kubernetes/workload?project=$PROJECT_ID
```

**BigQuery:**
```
https://console.cloud.google.com/bigquery?project=$PROJECT_ID&d=security_scans
```

**Cloud Logging:**
```
https://console.cloud.google.com/logs/query?project=$PROJECT_ID
# Filter: resource.type="k8s_pod" resource.labels.namespace_name="security-patch-agent"
```

**Monitoring Dashboards:**
```
https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID
```

---

## Useful Commands

### View Logs

```bash
# API container logs
kubectl logs -n security-patch-agent -l app=security-patch-agent -c api

# Worker container logs  
kubectl logs -n security-patch-agent -l app=security-patch-agent -c worker

# Scan job logs
kubectl logs -n security-patch-agent job/scan-<ID>
```

### List Resources

```bash
# All pods
kubectl get pods -n security-patch-agent

# All jobs (completed scans)
kubectl get jobs -n security-patch-agent

# Services
kubectl get svc -n security-patch-agent

# ConfigMaps
kubectl get configmap -n security-patch-agent
```

### Query Data

```bash
# Recent scans
curl -H "X-API-Key: $API_KEY" http://$API_IP/scans?limit=10 | jq .

# Specific scan
curl -H "X-API-Key: $API_KEY" http://$API_IP/scans/<SCAN_ID> | jq .

# BigQuery
bq query --project_id=$PROJECT_ID --use_legacy_sql=false \
  "SELECT * FROM security_scans.scans WHERE scan_mode='patch' ORDER BY timestamp DESC"
```

---

## Troubleshooting

### Pipeline fails at Terraform

**Error:** State bucket not found

**Fix:**
```bash
# Create state bucket (step 1.6)
gsutil mb gs://${PROJECT_ID}-terraform-state
```

### Pod stuck in Pending

```bash
kubectl describe pod <POD_NAME> -n security-patch-agent

# Common causes:
# - Insufficient quota
# - Workload Identity misconfigured
# - Image pull error
```

### Worker can't access Pub/Sub

```bash
# Check Workload Identity
kubectl get sa security-patch-agent -n security-patch-agent -o yaml \
  | grep "iam.gserviceaccount.com/email"

# Should show: security-patch-agent@PROJECT_ID.iam.gserviceaccount.com
```

### Webhook returns 401 Unauthorized

**Issue:** HMAC signature mismatch

**Fix:**
```bash
# Verify webhook secret matches
gcloud secrets versions access latest --secret=github-webhook-secret

# Update GitHub webhook with exact value
```

---

## 🎉 Installation Complete!

### What You Have

- ✅ **GKE Autopilot cluster** - Auto-scaling K8s
- ✅ **Event-driven architecture** - Pub/Sub + Jobs
- ✅ **LLM integration** - Gemini 2.5 Pro (Workload Identity)
- ✅ **Audit logging** - BigQuery
- ✅ **Monitoring** - Cloud Monitoring dashboards
- ✅ **Web UI + API** - http://<EXTERNAL_IP>

### Cost Estimate

~$750/month for 200 scans:
- GKE Autopilot: $500
- Vertex AI (Gemini): $200
- BigQuery + Storage + Pub/Sub: $50

### Next Steps

1. Add your repositories to whitelist (update ConfigMap)
2. Configure webhooks for automated PR scans
3. Review scan results in BigQuery
4. Customize monitoring dashboards

---

## Quick Reference

**API Endpoint:** `http://<EXTERNAL_IP>`  
**Web UI:** `http://<EXTERNAL_IP>/`  
**Health:** `http://<EXTERNAL_IP>/health`

**Secret Manager:**
- `github-token` - GitHub PAT
- `github-webhook-secret` - HMAC for webhooks

**GitHub Actions Secrets:**
- `GCP_PROJECT_ID`
- `GCP_SERVICE_ACCOUNT_KEY`
- `API_KEY_PRIMARY`
- `API_KEY_SECONDARY`

**kubectl Context:**
```bash
kubectl config use-context gke_${PROJECT_ID}_us-central1_code-vulnerability-scanner
```

---

**Support:** kannavkunal@gmail.com  
**Live Demo:** http://34.67.157.196/  
**Documentation:** [ARCHITECTURE.md](docs/SYSTEM_ARCHITECTURE_DIAGRAM.md)
