# Security Patch Agent - Installation Guide (Actual Steps)

This guide documents the actual installation steps taken to deploy the Security Patch Agent to GCP.

---

## 📝 Quick Summary

**Project ID**: `security-patch-agent-gcp-new`  
**Project Number**: `<YOUR_PROJECT_NUMBER>`

**Code Changes**: 
- ✅ `infrastructure/terraform/main.tf` - Terraform state bucket name
- ⚠️ **Optional**: `.github/workflows/full-deployment.yml` - Update `VULNERABLE_REPOS` to scan your own repositories (currently set to demo repos)

---

## Step 1: Clone the Repository

```bash
git clone https://github.com/YOUR-USERNAME/security-patch-agent-gcp-new
cd security-patch-agent-gcp-new
```

---

## Step 2: Create GCP Project

1. Go to: https://console.cloud.google.com/projectcreate
2. Create a new project:
   - **Project name**: `security-patch-agent-gcp-new`
   - **Project ID**: `security-patch-agent-gcp-new` (or auto-generated)
   - **Billing account**: Select your billing account
3. Note your **Project ID** and **Project Number**

⚠️ **IMPORTANT**: Billing must be enabled for this project (GKE, Vertex AI, etc. require billing)

---

## Step 3: Create Service Account

1. Go to: https://console.cloud.google.com/iam-admin/serviceaccounts?project=security-patch-agent-gcp-new
2. Click **"Create Service Account"**
3. Fill in:
   - **Service account name**: `github-gcp`
   - **Service account ID**: `github-gcp`
   - **Description**: `Service account for GitHub Actions deployment`
4. Click **"Create and Continue"**
5. Grant role: **Owner** (or Editor + additional permissions)
6. Click **"Done"**

**Result**: `github-gcp@security-patch-agent-gcp-new.iam.gserviceaccount.com`

---

## Step 4: Download Service Account Key

1. In the Service Accounts list, click on `github-gcp@security-patch-agent-gcp-new.iam.gserviceaccount.com`
2. Go to **"Keys"** tab
3. Click **"Add Key"** → **"Create new key"**
4. Select **JSON**
5. Click **"Create"**
6. Save the file (e.g., `security-patch-agent-gcp-new-xxxxx.json`)

---

## Step 5: Activate Service Account

```bash
# Activate the service account
gcloud auth activate-service-account \
  --key-file=/path/to/downloads/security-patch-agent-gcp-new-xxxxx.json

# Set the project
gcloud config set project security-patch-agent-gcp-new

# Verify active account
gcloud auth list

# Verify config
gcloud config list
```

**Expected output**:
```
ACTIVE  ACCOUNT
*       github-gcp@security-patch-agent-gcp-new.iam.gserviceaccount.com

[core]
account = github-gcp@security-patch-agent-gcp-new.iam.gserviceaccount.com
project = security-patch-agent-gcp-new
```

---

## Step 6: Enable Required APIs

```bash
gcloud services enable \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  pubsub.googleapis.com \
  bigquery.googleapis.com \
  secretmanager.googleapis.com \
  aiplatform.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com \
  cloudresourcemanager.googleapis.com
```

**Expected output**:
```
Operation "operations/acf.p2-YOUR_PROJECT_NUMBER-..." finished successfully.
```

---

## Step 7: Create GitHub Personal Access Token

1. Go to: https://github.com/settings/tokens
2. Click **"Generate new token (classic)"**
3. Fill in:
   - **Note**: `security-patch-agent-gcp-new`
   - **Expiration**: 90 days (or custom)
4. Select scopes:
   - ☑ **repo** (Full control of private repositories)
5. Click **"Generate token"**
6. **Copy and save the token** (starts with `ghp_...`) - you'll need it after deployment

**Note**: This token must have access to the repositories you want to scan.

---

## Step 8: Generate Webhook Secret

```bash
# Generate a random webhook secret
WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "Webhook secret: $WEBHOOK_SECRET"
echo $WEBHOOK_SECRET > webhook-secret.txt
```

**Save this value** - you'll need it:
1. After deployment to populate Secret Manager
2. When configuring GitHub webhooks

✅ **Webhook secret saved to**: `webhook-secret.txt`

---

## Step 10: Create Terraform State Bucket

```bash
# Create the bucket
gsutil mb -p security-patch-agent-gcp-new \
  -c STANDARD \
  -l us-central1 \
  gs://security-patch-agent-gcp-new-terraform-state

# Enable versioning
gsutil versioning set on gs://security-patch-agent-gcp-new-terraform-state

# Verify bucket created
gsutil ls -p security-patch-agent-gcp-new
```

**Expected output**:
```
Creating gs://security-patch-agent-gcp-new-terraform-state/...
Enabling versioning for gs://security-patch-agent-gcp-new-terraform-state/...
gs://security-patch-agent-gcp-new-terraform-state/
```

✅ **Bucket created**: `gs://security-patch-agent-gcp-new-terraform-state/`

---

## Step 11: Update Terraform Backend Configuration

Update the Terraform state bucket name to match the bucket created in Step 10.

```bash
# Update Terraform backend
cd infrastructure/terraform
sed -i '' 's/security-patch-agent-gcp-terraform-state/security-patch-agent-gcp-new-terraform-state/' main.tf

# Verify the change
grep "bucket =" main.tf
# Expected output: bucket = "security-patch-agent-gcp-new-terraform-state"
```

✅ **Changed**: `infrastructure/terraform/main.tf` line 16

**Note**: All other code is dynamic and reads project ID from GitHub Secrets (no other changes needed).

---

## Step 12: Commit the Terraform Change

```bash
# Make sure you're in the repo root
cd ~/path/to/security-patch-agent-gcp-new

# Stage the change
git add infrastructure/terraform/main.tf

# Commit
git commit -m "Update Terraform backend bucket for security-patch-agent-gcp-new"

# Push to your fork
git push origin main
```

---

## Step 13: (Optional) Update Repository Whitelist

⚠️ **IMPORTANT**: The default deployment scans only these 4 demo repositories:
- `https://github.com/kannavkunal/vulnerable-python-api`
- `https://github.com/kannavkunal/vulnerable-node-service`
- `https://github.com/kannavkunal/vulnerable-go-microservice`
- `https://github.com/kannavkunal/vulnerable-java-app`

**To scan your own repositories**, update `.github/workflows/full-deployment.yml`:

```bash
# Edit the workflow file
nano .github/workflows/full-deployment.yml

# Find line ~364 (search for "VULNERABLE_REPOS")
# Change the repository URLs to your own:
--from-literal=VULNERABLE_REPOS="https://github.com/YOUR-ORG/your-repo-1,https://github.com/YOUR-ORG/your-repo-2" \
```

⚠️ **Remember**: The GitHub token uploaded to Secret Manager in **Step 8** must have access to these repositories!

**Or keep the demo repos** for initial testing, then update later.

---

## Step 14: Set GitHub Repository Secrets

Go to your forked repository: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add these 4 secrets:

### 1. GCP_PROJECT_ID
- **Name**: `GCP_PROJECT_ID`
- **Value**: `security-patch-agent-gcp-new`

### 2. GCP_SERVICE_ACCOUNT_KEY
- **Name**: `GCP_SERVICE_ACCOUNT_KEY`
- **Value**: Paste the entire content of the JSON key file from Step 4
  ```bash
  # View the key file content
  cat /path/to/downloads/security-patch-agent-gcp-new-xxxxx.json
  # Copy the entire JSON output
  ```

### 3. API_KEY_PRIMARY
- **Name**: `API_KEY_PRIMARY`
- **Value**: Generate with:
  ```bash
  openssl rand -hex 32
  ```

### 4. API_KEY_SECONDARY
- **Name**: `API_KEY_SECONDARY`
- **Value**: Generate with:
  ```bash
  openssl rand -hex 32
  ```

✅ **Verify**: You should have 4 repository secrets set

---

## Step 15: Run GitHub Actions Deployment

1. Go to your GitHub repository: https://github.com/YOUR-USERNAME/security-patch-agent-gcp-new
2. Click **"Actions"** tab
3. Click **"Full Deployment"** workflow (left sidebar)
4. Click **"Run workflow"** button (top right)
5. Keep all defaults checked:
   - ☑ Deploy infrastructure (Terraform)
   - ☑ Build and push Docker images
   - ☑ Deploy application to GKE
6. Click **"Run workflow"**

**Wait ~15-20 minutes** for deployment to complete. Watch for all green checkmarks ✅.

---

## Step 16: Populate Secret Manager Values

**IMPORTANT:** After the workflow completes successfully, Terraform creates **empty secret containers**. You must populate them with actual values:

```bash
# Set project
export PROJECT_ID=security-patch-agent-gcp-new

# 1. Add GitHub Token (from Step 7)
# Replace ghp_YOUR_TOKEN with your actual GitHub token
echo -n "ghp_YOUR_ACTUAL_GITHUB_TOKEN" | gcloud secrets versions add github-token \
  --project=$PROJECT_ID \
  --data-file=-

# 2. Add Webhook Secret (from Step 8 or webhook-secret.txt file)
cat webhook-secret.txt | gcloud secrets versions add github-webhook-secret \
  --project=$PROJECT_ID \
  --data-file=-

# 3. Verify secrets are populated
gcloud secrets versions access latest --secret=github-token --project=$PROJECT_ID
gcloud secrets versions access latest --secret=github-webhook-secret --project=$PROJECT_ID
```

**Expected output:**
```
Created version [1] of the secret [github-token].
Created version [1] of the secret [github-webhook-secret].
```

✅ **Secrets are now ready to use**

---

## Step 17: Get LoadBalancer IP

After the GitHub Actions workflow completes, the **LoadBalancer External IP** will be displayed in the workflow output:

1. Go to **Actions** → **Full Deployment** → Latest run
2. Expand **Step 5: Deploy Application**
3. Look for the output showing the LoadBalancer IP:
   ```
   External IP: XX.XX.XX.XX
   ```
4. Copy this IP address

**Or retrieve it manually:**

```bash
# Activate service account
gcloud auth activate-service-account --key-file=/path/to/downloads/security-patch-agent-gcp-new-xxxxx.json

# Get cluster credentials
gcloud container clusters get-credentials code-vulnerability-scanner \
  --region=us-central1 \
  --project=security-patch-agent-gcp-new

# Get LoadBalancer IP
kubectl get svc security-patch-agent -n security-patch-agent --insecure-skip-tls-verify

# Copy the EXTERNAL-IP from the output
export API_IP=<paste-external-ip-here>
```

---

## Step 18: Verify Deployment

```bash
# Activate service account (if not already active)
gcloud auth activate-service-account --key-file=/path/to/downloads/security-patch-agent-gcp-new-xxxxx.json

# Set project
gcloud config set project security-patch-agent-gcp-new

# Get cluster credentials
gcloud container clusters get-credentials code-vulnerability-scanner \
  --region=us-central1 \
  --project=security-patch-agent-gcp-new

# Check pods are running (should show 1 pod with 2/2 READY)
kubectl get pods -n security-patch-agent --insecure-skip-tls-verify

# Expected output:
# NAME                                    READY   STATUS    RESTARTS   AGE
# security-patch-agent-xxxxxxxxxx-xxxxx   2/2     Running   0          5m

# Check deployment (should show 1/1 replicas)
kubectl get deployment security-patch-agent -n security-patch-agent --insecure-skip-tls-verify

# Expected output:
# NAME                   READY   UP-TO-DATE   AVAILABLE   AGE
# security-patch-agent   1/1     1            1           7m

# Get service details
kubectl get svc security-patch-agent -n security-patch-agent --insecure-skip-tls-verify

# Test the API (use the EXTERNAL-IP from above)
curl http://$API_IP/health
# Expected: {"status":"healthy","model":"gemini-2.5-pro"}

# List repositories
curl http://$API_IP/repositories
# Expected: {"count":4,"repositories":[...]}
```

**Understanding the output:**
- **2/2 READY**: 2 containers (API + Worker) running in 1 pod
- **1/1 replicas**: 1 pod total (as configured)
- If you see a second pod in "Terminating" status, that's normal - it's a rolling update cleanup

---

## Step 19: Configure GitHub Webhooks (REVIEW Mode)

⚠️ **Optional but Recommended**: This enables automatic PR scanning - whenever a PR is opened or updated, the system automatically scans it and posts security findings as PR comments.

**Webhook Configuration Details** (same for all repositories):

- **Payload URL**: `http://<EXTERNAL_IP>/webhook/github` (replace with your LoadBalancer IP from Step 17)
- **Content type**: `application/json`
- **Secret**: Use the webhook secret from Step 8 (`webhook-secret.txt` or retrieve from Secret Manager)
- **Events**: Select "Pull requests" only
- **Active**: ✅ Yes

**Retrieve webhook secret** (if needed):

```bash
# Get the webhook secret from Secret Manager
gcloud secrets versions access latest \
  --secret=github-webhook-secret \
  --project=security-patch-agent-gcp-new
```

---

### Configure Webhooks for All 4 Repositories

The following repositories are configured in `VULNERABLE_REPOS` and need webhooks:

#### Repository 1: vulnerable-python-api

1. Go to: [https://github.com/kannavkunal/vulnerable-python-api/settings/hooks/new](https://github.com/kannavkunal/vulnerable-python-api/settings/hooks/new)
2. Fill in:
   - **Payload URL**: `http://<EXTERNAL_IP>/webhook/github`
   - **Content type**: `application/json`
   - **Secret**: `<paste-webhook-secret-from-step-8>`
   - **Which events**: ○ Let me select individual events → ☑ Pull requests
   - ☑ **Active**
3. Click **"Add webhook"**

#### Repository 2: vulnerable-node-service

1. Go to: [https://github.com/kannavkunal/vulnerable-node-service/settings/hooks/new](https://github.com/kannavkunal/vulnerable-node-service/settings/hooks/new)
2. Use the same configuration as above
3. Click **"Add webhook"**

#### Repository 3: vulnerable-go-microservice

1. Go to: [https://github.com/kannavkunal/vulnerable-go-microservice/settings/hooks/new](https://github.com/kannavkunal/vulnerable-go-microservice/settings/hooks/new)
2. Use the same configuration as above
3. Click **"Add webhook"**

#### Repository 4: vulnerable-java-app

1. Go to: [https://github.com/kannavkunal/vulnerable-java-app/settings/hooks/new](https://github.com/kannavkunal/vulnerable-java-app/settings/hooks/new)
2. Use the same configuration as above
3. Click **"Add webhook"**

---

### Verify Webhooks

After creating all webhooks, verify they're active:

1. Go to each repository's webhook settings page (e.g., `https://github.com/USER/REPO/settings/hooks`)
2. Look for a green checkmark ✅ next to each webhook
3. Click on the webhook to see recent deliveries

**Test it**: Create a test PR in one of the repositories to trigger REVIEW mode!

---

### What Happens When a PR is Created/Updated?

1. GitHub sends a webhook event to `http://<EXTERNAL_IP>/webhook/github`
2. The API validates the HMAC signature using the webhook secret
3. The system scans the PR branch
4. It compares vulnerabilities against the base branch
5. Only **NEW** vulnerabilities (not in base) are reported
6. A comment is posted on the PR with findings

**Note**: The GitHub token in Secret Manager (from Step 16) must have write access to these repositories to post PR comments.

---

## 🎉 Installation Complete!

Your Security Patch Agent is now deployed and ready!

**Access Points:**
- **Web UI**: `http://<EXTERNAL_IP>/`
- **API**: `http://<EXTERNAL_IP>`
- **Health Check**: `http://<EXTERNAL_IP>/health`

**Next Steps:** See testing commands in the Commands Reference section below.

---

## Commands Reference

### Check Active Configuration
```bash
gcloud config list
gcloud auth list
```

### List Secrets
```bash
gcloud secrets list --project=security-patch-agent-gcp-new
```

### View Secret Values
```bash
# View GitHub token
gcloud secrets versions access latest \
  --secret=github-token \
  --project=security-patch-agent-gcp-new

# View webhook secret
gcloud secrets versions access latest \
  --secret=github-webhook-secret \
  --project=security-patch-agent-gcp-new
```

### Check Storage Buckets
```bash
# List buckets
gsutil ls -p security-patch-agent-gcp-new

# Check bucket versioning
gsutil versioning get gs://security-patch-agent-gcp-new-terraform-state
```

### Check Enabled Services
```bash
gcloud services list --enabled --project=security-patch-agent-gcp-new
```

---

## Project Details

- **Project ID**: `security-patch-agent-gcp-new`
- **Project Number**: `YOUR_PROJECT_NUMBER`
- **Service Account**: `github-gcp@security-patch-agent-gcp-new.iam.gserviceaccount.com`
- **Region**: `us-central1` (default)
- **Webhook Secret**: `xxxxx-REDACTED-WEBHOOK-SECRET-xxxxx` (also in `webhook-secret.txt`)

---

## Secrets To Be Created

- [ ] `github-token` - Created by Terraform (empty), populated in Step 16
- [ ] `github-webhook-secret` - Created by Terraform (empty), populated in Step 16
- [x] GitHub token generated and saved (Step 7)
- [x] Webhook secret generated and saved to `webhook-secret.txt` (Step 8)

## Resources Created

- [x] GCS Bucket: `gs://security-patch-agent-gcp-new-terraform-state/` (with versioning enabled)

## Code Changes Made

- [x] Updated Terraform backend bucket name in `infrastructure/terraform/main.tf`
  - Changed: `security-patch-agent-gcp-terraform-state` → `security-patch-agent-gcp-new-terraform-state`
- [x] All other code is dynamic (reads project ID from environment variables)

## GitHub Secrets Created

- [x] `GCP_PROJECT_ID` - Project identifier
- [x] `GCP_SERVICE_ACCOUNT_KEY` - Service account JSON key
- [x] `API_KEY_PRIMARY` - Primary API key for authentication
- [x] `API_KEY_SECONDARY` - Secondary API key for authentication

## Pending

- [ ] (Optional) Update VULNERABLE_REPOS in `.github/workflows/full-deployment.yml` for your own repositories
- [ ] Commit and push changes to GitHub (if any)
- [ ] Run GitHub Actions deployment workflow (Step 15)
- [ ] Populate Secret Manager values (Step 16)
- [ ] Verify deployment (Step 17)

---

**Status**: Ready for Deployment - Steps 1-14 Complete, Steps 15-17 Documented

---

## 🧹 Cleanup Guide

When you want to delete all resources and stop incurring costs:

### Option 1: GitHub Actions Cleanup (Recommended)

1. Go to **Actions** → **"Cleanup - Destroy All Resources"**
2. Click **"Run workflow"**
3. Type **"DESTROY"** to confirm
4. Click **"Run workflow"**

**This will delete:**
- ✅ GKE cluster
- ✅ Pub/Sub resources
- ✅ BigQuery dataset
- ✅ GCS evidence bucket
- ✅ Secret Manager secrets
- ✅ Artifact Registry repository
- ✅ Terraform-created service account
- ✅ Monitoring dashboards & alerts

**Cost after this**: ~$0.10/month (just the Terraform state bucket)

---

### Option 2: Complete Manual Cleanup (100% Clean)

After running the GitHub Actions cleanup, delete these manually created resources:

```bash
# 1. Delete Terraform state bucket (created in Step 10)
gsutil rm -r gs://security-patch-agent-gcp-new-terraform-state

# 2. Delete manual service account (created in Step 3)
gcloud iam service-accounts delete github-gcp@security-patch-agent-gcp-new.iam.gserviceaccount.com \
  --project=security-patch-agent-gcp-new

# 3. Delete service account key file (downloaded in Step 4)
rm /path/to/downloads/security-patch-agent-gcp-new-xxxxx.json

# 4. Delete GitHub Secrets
# Go to GitHub repo → Settings → Secrets → Delete all 4 secrets

# 5. (Nuclear option) Delete entire GCP project
gcloud projects delete security-patch-agent-gcp-new
```

**Cost after complete cleanup**: $0/month

---

### Quick Cleanup Commands

```bash
# Set project ID
export PROJECT_ID=security-patch-agent-gcp-new

# Delete state bucket
gsutil rm -r gs://${PROJECT_ID}-terraform-state

# Delete manual service account
gcloud iam service-accounts delete github-gcp@${PROJECT_ID}.iam.gserviceaccount.com \
  --project=$PROJECT_ID --quiet

# Verify everything is deleted
gcloud container clusters list --project=$PROJECT_ID
gcloud pubsub topics list --project=$PROJECT_ID
bq ls -d --project_id=$PROJECT_ID
gsutil ls -p $PROJECT_ID
```

---

**Status**: Installation guide complete
