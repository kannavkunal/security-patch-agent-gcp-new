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
6. **Copy the token** (starts with `ghp_...`)

**Note**: This token must have access to the repositories you want to scan (configured in Step 13).

---

## Step 8: Store GitHub Token in Secret Manager

```bash
# Replace with your actual token
echo -n "ghp_YOUR_ACTUAL_TOKEN" | gcloud secrets create github-token \
  --project=security-patch-agent-gcp-new \
  --data-file=- \
  --replication-policy="automatic"
```

**Example** (DO NOT use this token - it's just an example):
```bash
echo -n "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" | gcloud secrets create github-token \
  --project=security-patch-agent-gcp-new \
  --data-file=- \
  --replication-policy="automatic"
```

**Expected output**:
```
Created version [1] of the secret [github-token].
```

---

## Step 9: Create GitHub Webhook Secret

```bash
# Generate a random webhook secret
WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "Save this webhook secret: $WEBHOOK_SECRET"
echo $WEBHOOK_SECRET > webhook-secret.txt

# Store in Secret Manager
echo -n "$WEBHOOK_SECRET" | gcloud secrets create github-webhook-secret \
  --project=security-patch-agent-gcp-new \
  --data-file=- \
  --replication-policy="automatic"
```

**Actual output**:
```
Save this webhook secret: xxxxx-REDACTED-WEBHOOK-SECRET-xxxxx
Created version [1] of the secret [github-webhook-secret].
```

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

## Step 15: [CONTINUE FROM HERE]

**Next steps to complete:**

1. Commit and push code changes to GitHub
2. Run GitHub Actions deployment workflow
3. Test the deployment

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

## Secrets Created

- [x] `github-token` - GitHub Personal Access Token
- [x] `github-webhook-secret` - HMAC secret for GitHub webhooks (saved in `webhook-secret.txt`)

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
- [ ] Commit and push changes to GitHub
- [ ] Run GitHub Actions deployment workflow
- [ ] Test the deployment

---

**Status**: In Progress - Completed Steps 1-14
