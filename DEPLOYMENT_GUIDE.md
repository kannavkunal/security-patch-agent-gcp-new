# Complete Deployment Guide - Security Patch Agent

**End-to-end deployment from zero to production in ~30 minutes**

---

## 📋 Prerequisites

- Google Cloud Platform account with billing enabled
- GitHub account
- Local machine with:
  - `gcloud` CLI installed ([install guide](https://cloud.google.com/sdk/docs/install))
  - `git` installed
  - `kubectl` installed ([install guide](https://kubernetes.io/docs/tasks/tools/))

---

## 🚀 Step-by-Step Deployment

### Step 1: Create GCP Project

**1.1 Go to GCP Console:**
- Visit: https://console.cloud.google.com/

**1.2 Create New Project:**
- Click **"Select a project"** dropdown (top left)
- Click **"New Project"**
- **Project name:** `security-patch-agent-gcp` (or your choice)
- **Project ID:** Will be auto-generated (e.g., `security-patch-agent-gcp`)
- Click **"Create"**

**1.3 Enable Billing:**
- Go to: https://console.cloud.google.com/billing
- Link a billing account to your project
- ⚠️ **Required** - APIs won't work without billing

**1.4 Copy your Project ID:**
```
Example: security-patch-agent-gcp
```

---

### Step 2: Create Service Account

**2.1 Go to IAM & Admin:**
- Visit: https://console.cloud.google.com/iam-admin/serviceaccounts
- Make sure your new project is selected (top dropdown)

**2.2 Create Service Account:**
- Click **"+ CREATE SERVICE ACCOUNT"**
- **Service account name:** `github-gcp`
- **Service account ID:** `github-gcp` (auto-filled)
- **Description:** `GitHub Actions deployment service account`
- Click **"CREATE AND CONTINUE"**

**2.3 Grant Permissions:**
- **Select a role:** Choose **"Owner"**
  - (For production, use granular roles: Container Admin, Artifact Registry Admin, etc.)
- Click **"CONTINUE"**
- Click **"DONE"**

**2.4 Create JSON Key:**
- Find your new service account in the list
- Click the **3 dots** (⋮) on the right → **"Manage keys"**
- Click **"ADD KEY"** → **"Create new key"**
- Select **"JSON"**
- Click **"CREATE"**
- **Save the downloaded file** (e.g., `security-patch-agent-gcp-xxxx.json`)

---

### Step 3: Enable Required GCP APIs

**3.1 Authenticate with Service Account:**

```bash
# Use the JSON key you just downloaded
gcloud auth activate-service-account \
  --key-file=/Users/YOUR_USERNAME/Downloads/security-patch-agent-gcp-xxxx.json

# Set your project
gcloud config set project YOUR_PROJECT_ID

# Verify authentication
gcloud auth list
```

**3.2 Enable APIs (one command):**

```bash
gcloud services enable container.googleapis.com artifactregistry.googleapis.com pubsub.googleapis.com bigquery.googleapis.com secretmanager.googleapis.com aiplatform.googleapis.com monitoring.googleapis.com logging.googleapis.com compute.googleapis.com iam.googleapis.com
```

**Expected output:**
```
Operation "operations/..." finished successfully.
```

⏱️ This takes ~1-2 minutes.

---

### Step 4: Fork/Clone the Repository

**Option A: Fork the Repository (Recommended)**

1. Go to: https://github.com/kannavkunal/security-patch-agent-gcp
2. Click **"Fork"** button (top right)
3. Select your GitHub account
4. Wait for fork to complete

**Option B: Clone the Repository**

```bash
# Clone to your local machine
git clone https://github.com/kannavkunal/security-patch-agent-gcp.git
cd security-patch-agent-gcp

# If you want your own repo, create it on GitHub first, then:
git remote set-url origin git@github.com:YOUR_USERNAME/YOUR_REPO_NAME.git
git push -u origin main
```

---

### Step 5: Set GitHub Secrets

**5.1 Go to GitHub Repository Settings:**
- Your forked repo: `https://github.com/YOUR_USERNAME/security-patch-agent-gcp`
- Click **"Settings"** tab
- Click **"Secrets and variables"** → **"Actions"**

**5.2 Add the following 4 secrets:**

Click **"New repository secret"** for each:

#### Secret 1: `GCP_PROJECT_ID`
```
YOUR_PROJECT_ID
```
Example: `security-patch-agent-gcp`

#### Secret 2: `GCP_SERVICE_ACCOUNT_KEY`

Copy the **entire contents** of your JSON key file:

```bash
# Mac/Linux - copies to clipboard
cat /Users/YOUR_USERNAME/Downloads/security-patch-agent-gcp-xxxx.json | pbcopy

# Or manually open the file and copy all contents
```

Paste the entire JSON (from `{` to `}`) as the secret value.

#### Secret 3: `API_KEY_PRIMARY`

Generate a random API key:

```bash
openssl rand -hex 32
```

Copy the output and paste as secret.

#### Secret 4: `API_KEY_SECONDARY`

Generate another random API key:

```bash
openssl rand -hex 32
```

Copy the output and paste as secret.

**✅ Verify all 4 secrets are added:**
- GCP_PROJECT_ID
- GCP_SERVICE_ACCOUNT_KEY
- API_KEY_PRIMARY
- API_KEY_SECONDARY

---

### Step 6: Create GitHub Token

**6.1 Create GitHub Personal Access Token:**

1. Go to: https://github.com/settings/tokens/new
2. **Note:** `Security Patch Agent Token`
3. **Expiration:** 90 days (or your preference)
4. **Select scopes:**
   - ✅ `repo` (all)
   - ✅ `workflow`
5. Click **"Generate token"**
6. **Copy the token** (you won't see it again!)

**6.2 Add Token to GCP Secret Manager:**

```bash
# Replace YOUR_GITHUB_TOKEN with the token you just created
echo -n "YOUR_GITHUB_TOKEN" | \
  gcloud secrets create github-token \
  --project=YOUR_PROJECT_ID \
  --data-file=- \
  --replication-policy="automatic"
```

**Expected output:**
```
Created secret [github-token].
```

---

### Step 7: Deploy Infrastructure and Application

**7.1 Go to GitHub Actions:**
- Your repo: `https://github.com/YOUR_USERNAME/security-patch-agent-gcp`
- Click **"Actions"** tab

**7.2 Run Full Deployment Workflow:**

1. Click **"Full Deployment Pipeline"** on the left
2. Click **"Run workflow"** dropdown (right side)
3. Configure deployment options:
   - ✅ **Deploy infrastructure:** `true`
   - **Infrastructure components:** `all`
   - ✅ **Deploy application:** `true`
   - **Environment:** `production`
   - ✅ **Run security scan:** `true`
   - ✅ **Run tests:** `true`
4. Click green **"Run workflow"** button

**7.3 Monitor Progress:**

Watch the workflow progress in real-time:
- ✅ Step 1: Security Scan (~2 min)
- ✅ Step 2: Build and Test (~3 min)
- ✅ Step 3: Deploy Infrastructure (~8 min)
- ✅ Step 4: Build and Push Docker Image (~2 min)
- ✅ Step 5: Deploy to GKE (~5 min)
- ✅ Step 6: Integration Tests (~2 min)

**Total time: ~15-20 minutes**

---

### Step 8: Verify Deployment

**8.1 Get GKE Cluster Credentials:**

```bash
gcloud container clusters get-credentials code-vulnerability-scanner \
  --region=us-central1 \
  --project=YOUR_PROJECT_ID
```

**8.2 Check Pods are Running:**

```bash
kubectl get pods -n security-patch-agent
```

**Expected output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
security-patch-agent-xxxx-yyyy            2/2     Running   0          5m
```

**8.3 Get LoadBalancer IP:**

```bash
kubectl get svc security-patch-agent -n security-patch-agent
```

**Expected output:**
```
NAME                   TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)
security-patch-agent   LoadBalancer   10.x.x.x        34.x.x.x         80:xxxxx/TCP
```

Copy the **EXTERNAL-IP** (e.g., `34.171.214.25`)

**8.4 Test Health Endpoint:**

```bash
# Replace with your LoadBalancer IP
curl http://34.171.214.25/health
```

**Expected output:**
```json
{"status":"healthy","model":"gemini-2.5-pro"}
```

✅ **Deployment successful!**

---

## 🎯 Post-Deployment: Test the System

### Test 1: Trigger a Security Scan

**1.1 Get API Key:**

```bash
kubectl get secret security-patch-agent-api-keys \
  -n security-patch-agent \
  -o jsonpath='{.data.api-keys}' | base64 -d | cut -d',' -f1
```

**1.2 Trigger PATCH Mode Scan:**

```bash
# Replace LOADBALANCER_IP and API_KEY
curl -X POST http://LOADBALANCER_IP/scan \
  -H "Content-Type: application/json" \
  -H "X-API-Key: API_KEY" \
  -d '{
    "repo_url": "https://github.com/kannavkunal/vulnerable-python-api",
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

### Test 2: Check Scan Progress

**2.1 Watch Kubernetes Job:**

```bash
kubectl get jobs -n security-patch-agent
```

**2.2 Check Job Logs:**

```bash
# Get job name from above, then:
kubectl logs -n security-patch-agent job/JOB_NAME -f
```

### Test 3: Verify Results

**3.1 Check BigQuery (Audit Logs):**

```bash
bq query --use_legacy_sql=false \
  'SELECT scan_id, timestamp, repo_name, status, vulnerabilities_found 
   FROM `YOUR_PROJECT_ID.security_scans.scans` 
   ORDER BY timestamp DESC 
   LIMIT 5'
```

**3.2 Check GCS (Evidence Files):**

```bash
gsutil ls gs://security-patch-evidence-YOUR_PROJECT_ID/
```

**3.3 Check GitHub (PR Created):**
- Go to: https://github.com/kannavkunal/vulnerable-python-api/pulls
- You should see a new PR with security patches!

---

## 🌐 Access the Web UI

Open your browser and go to:
```
http://LOADBALANCER_IP/static/index.html
```

**Features:**
- Enter API key
- Trigger scans via web interface
- View scan history
- No installation required

---

## 📊 Monitoring and Observability

### Cloud Console Links

**GKE Workloads:**
```
https://console.cloud.google.com/kubernetes/workload?project=YOUR_PROJECT_ID
```

**Cloud Monitoring Dashboards:**
```
https://console.cloud.google.com/monitoring/dashboards?project=YOUR_PROJECT_ID
```

**Cloud Logging:**
```
https://console.cloud.google.com/logs/query?project=YOUR_PROJECT_ID
```

**BigQuery (Audit Database):**
```
https://console.cloud.google.com/bigquery?project=YOUR_PROJECT_ID
```

**Cloud Storage (Evidence):**
```
https://console.cloud.google.com/storage/browser?project=YOUR_PROJECT_ID
```

### View Metrics

```bash
# Pod status
kubectl get pods -n security-patch-agent

# Service status
kubectl get svc -n security-patch-agent

# Recent logs
kubectl logs -n security-patch-agent deployment/security-patch-agent -c api --tail=50

# Worker logs
kubectl logs -n security-patch-agent deployment/security-patch-agent -c worker --tail=50
```

---

## 🧹 Cleanup - Delete All Resources

**When you're done testing and want to delete everything:**

### Option 1: GitHub Actions Cleanup Workflow

1. Go to **Actions** → **"Cleanup - Destroy All Resources"**
2. Click **"Run workflow"**
3. Type **`DESTROY`** in the confirmation field
4. Click **"Run workflow"**
5. Wait ~5 minutes for all resources to be deleted

### Option 2: Manual Cleanup Script

```bash
# Clone the repo if not already
cd security-patch-agent-gcp

# Set environment variable
export GCP_PROJECT_ID="YOUR_PROJECT_ID"

# Run cleanup script
./cleanup.sh
```

**Expected cost after cleanup:** $0/month

---

## 🔐 Security Best Practices

### For Production Deployment:

**1. Use Granular IAM Roles:**

Instead of `roles/owner`, grant specific permissions:

```bash
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:github-gcp@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.admin"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:github-gcp@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.admin"

# ... add other specific roles
```

**2. Rotate Service Account Keys:**
- Delete old keys after 90 days
- Create new keys and update GitHub Secrets

**3. Enable Workload Identity:**
- Already configured in the deployment
- Pods use Workload Identity instead of service account keys

**4. Restrict API Access:**
- Update the repository whitelist in `app/worker.py`
- Add your own repositories to the `ALLOWED_REPOS` list

**5. Set Budget Alerts:**
```bash
# Set a budget alert in GCP Console
https://console.cloud.google.com/billing/budgets
```

---

## 💰 Cost Breakdown

**Estimated Monthly Cost: ~$750**

| Service | Cost/month | Notes |
|---------|-----------|-------|
| GKE Cluster (e2-medium) | ~$50 | Regional cluster, 1 node |
| Vertex AI (Gemini 2.5 Pro) | ~$650 | Usage-based, depends on scan volume |
| BigQuery Storage | ~$5 | First 10GB free, then $0.02/GB |
| Cloud Storage | ~$5 | Standard storage |
| Pub/Sub | ~$5 | 10GB/month included |
| Networking | ~$10 | LoadBalancer + egress |
| Secret Manager | ~$1 | 6 secrets × ~100 accesses/month |
| Monitoring | Free | Included in GCP |

**Cost Optimization:**
- Use GKE Autopilot mode (saves ~30%)
- Reduce scan frequency
- Use smaller GKE node sizes
- Enable committed use discounts

---

## ❓ Troubleshooting

### Issue: Workflow fails at "Deploy Infrastructure"

**Solution:** Check if billing is enabled
```bash
gcloud beta billing projects describe YOUR_PROJECT_ID
```

### Issue: Pods stuck in "Pending" state

**Solution:** Check GKE node provisioning
```bash
kubectl describe pod -n security-patch-agent POD_NAME
```

### Issue: "Permission denied" errors

**Solution:** Verify service account has required roles
```bash
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:github-gcp@*"
```

### Issue: GitHub token not working

**Solution:** Verify secret exists in Secret Manager
```bash
gcloud secrets versions access latest --secret="github-token"
```

### Issue: Deployment works but scans fail

**Solution:** Check worker logs
```bash
kubectl logs -n security-patch-agent deployment/security-patch-agent -c worker --tail=100
```

---

## 📞 Support

- **Documentation:** See [README.md](README.md) and [INSTALLATION.md](INSTALLATION.md)
- **Issues:** https://github.com/kannavkunal/security-patch-agent-gcp/issues
- **Email:** kannavkunal@gmail.com

---

## ✅ Quick Checklist

Before running deployment, verify:

- [ ] GCP project created with billing enabled
- [ ] Service account created with Owner role
- [ ] Service account JSON key downloaded
- [ ] 10+ APIs enabled in GCP
- [ ] Repository forked/cloned
- [ ] 4 GitHub Secrets set (GCP_PROJECT_ID, GCP_SERVICE_ACCOUNT_KEY, API keys)
- [ ] GitHub Personal Access Token created
- [ ] GitHub token added to GCP Secret Manager

**Ready?** Run the "Full Deployment Pipeline" workflow! 🚀

---

**Total setup time:** ~30 minutes  
**Deployment time:** ~15-20 minutes  
**Total time to production:** ~45-50 minutes
