# Guide: Deploy to a Different GCP Project

This guide explains how to deploy the Security Patch Agent to a new GCP project by **only updating GitHub Secrets**—no code changes required.

---

## 🎯 One-Step Project Switch

All project-specific values are now controlled by **GitHub Secrets**. Change the project in one place, and everything updates automatically.

### Step 1: Update GitHub Secrets

Go to your GitHub repository → **Settings** → **Secrets and variables** → **Actions** → Update these secrets:

| Secret Name | Current Value | New Value (Example) |
|------------|---------------|---------------------|
| `GCP_PROJECT_ID` | `YOUR_PROJECT_ID` | `your-new-project-id` |
| `GCP_SA_KEY` | (current service account key) | (new project's SA key) |

**That's it!** All workflows will now use the new project.

---

## 📋 What Gets Updated Automatically

When you change `GCP_PROJECT_ID` secret, these workflows automatically use the new project:

✅ **build-and-test.yml** - Builds Docker images to new project's Artifact Registry  
✅ **deploy-application.yml** - Deploys to new project's GKE cluster  
✅ **full-deployment.yml** - Complete infrastructure + app deployment  
✅ **cleanup.yml** - Cleanup resources in new project  

---

## 🚀 Complete New Project Deployment

### Prerequisites

1. **Create GCP Project:**
   ```bash
   gcloud projects create YOUR-NEW-PROJECT-ID --name="Security Patch Agent"
   gcloud config set project YOUR-NEW-PROJECT-ID
   ```

2. **Enable Required APIs:**
   ```bash
   gcloud services enable \
     container.googleapis.com \
     artifactregistry.googleapis.com \
     pubsub.googleapis.com \
     bigquery.googleapis.com \
     secretmanager.googleapis.com \
     aiplatform.googleapis.com \
     monitoring.googleapis.com
   ```

3. **Create Service Account:**
   ```bash
   gcloud iam service-accounts create github-actions \
     --display-name="GitHub Actions Deployment"
   
   # Grant necessary roles
   gcloud projects add-iam-policy-binding YOUR-NEW-PROJECT-ID \
     --member="serviceAccount:github-actions@YOUR-NEW-PROJECT-ID.iam.gserviceaccount.com" \
     --role="roles/owner"
   
   # Create key
   gcloud iam service-accounts keys create key.json \
     --iam-account=github-actions@YOUR-NEW-PROJECT-ID.iam.gserviceaccount.com
   ```

4. **Update GitHub Secrets:**
   - `GCP_PROJECT_ID`: `YOUR-NEW-PROJECT-ID`
   - `GCP_SA_KEY`: Contents of `key.json` file

---

## 🔧 Deploy Infrastructure & Application

### Option 1: Using GitHub Actions (Recommended)

1. **Go to GitHub Actions:**
   - Navigate to your repo → **Actions** tab
   - Select **"Full Deployment"** workflow
   - Click **"Run workflow"**
   - Choose deployment options
   - Click **"Run workflow"** button

2. **Wait for completion** (~10-15 minutes):
   - Infrastructure provisioning (GKE, Pub/Sub, BigQuery, etc.)
   - Application deployment
   - Monitoring setup

3. **Get LoadBalancer IP:**
   ```bash
   kubectl get svc -n security-patch-agent security-patch-agent
   ```

### Option 2: Manual Terraform + kubectl

1. **Clone repository:**
   ```bash
   git clone https://github.com/kannavkunal/security-patch-agent.git
   cd security-patch-agent
   ```

2. **Update Terraform variables** (only if not using GitHub Actions):
   ```bash
   # Edit infrastructure/terraform/variables.tf
   # Change: default = "YOUR_PROJECT_ID"
   # To:     default = "YOUR-NEW-PROJECT-ID"
   ```

3. **Deploy infrastructure:**
   ```bash
   cd infrastructure/terraform
   
   # Update backend bucket name (if using remote state)
   # Edit main.tf line 16: bucket = "YOUR-NEW-PROJECT-ID-terraform-state"
   
   # Create state bucket
   gsutil mb -p YOUR-NEW-PROJECT-ID -l us-central1 gs://YOUR-NEW-PROJECT-ID-terraform-state
   
   # Deploy
   terraform init
   terraform apply -auto-approve
   ```

4. **Add secrets to Secret Manager:**
   ```bash
   # GitHub token
   echo -n "YOUR_GITHUB_TOKEN" | \
     gcloud secrets create github-token --data-file=-
   
   # Webhook secret
   echo -n "YOUR_WEBHOOK_SECRET" | \
     gcloud secrets create github-webhook-secret --data-file=-
   
   # API keys (comma-separated)
   echo -n "$(openssl rand -hex 32),$(openssl rand -hex 32)" | \
     gcloud secrets create security-patch-agent-api-keys --data-file=-
   ```

5. **Deploy application:**
   ```bash
   cd ../../deployment/k8s-manifests
   kubectl apply -f .
   ```

---

## ✅ Verification

### Check Deployment Status

```bash
# Check all resources
kubectl get all -n security-patch-agent

# Get LoadBalancer IP
kubectl get svc -n security-patch-agent

# Check API health
LB_IP=$(kubectl get svc security-patch-agent -n security-patch-agent -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$LB_IP/health
```

### Expected Output

```json
{"status":"healthy","model":"gemini-2.5-pro"}
```

---

## 🧹 Cleanup (Delete All Resources)

### Option 1: GitHub Actions

1. Go to **Actions** tab → **"Cleanup - Destroy All Resources"**
2. Click **"Run workflow"**
3. Type **"DESTROY"** to confirm
4. Click **"Run workflow"** button

### Option 2: Script

```bash
# Set environment variables
export GCP_PROJECT_ID="YOUR-NEW-PROJECT-ID"
export GCP_REGION="us-central1"
export GKE_CLUSTER="code-vulnerability-scanner"

# Run cleanup
./cleanup.sh
```

### Option 3: Terraform

```bash
cd infrastructure/terraform
terraform destroy -auto-approve
```

---

## 📊 Project-Specific Resources

These resources will be created in the new project:

### Compute
- **GKE Cluster:** `code-vulnerability-scanner` (us-central1)
- **Artifact Registry:** `security-patch-agent` (Docker images)

### Storage & Data
- **BigQuery Dataset:** `security_scans` (scan analytics)
- **Cloud Storage Bucket:** `security-patch-evidence-{project-id}` (CVSS reports)

### Messaging
- **Pub/Sub Topic:** `security-scan-events`
- **Pub/Sub Subscription:** `security-scan-events-sub`

### Security
- **Secret Manager Secrets:**
  - `github-token` (GitHub PAT)
  - `github-webhook-secret` (HMAC validation)
  - `security-patch-agent-api-keys` (API authentication)

### Monitoring
- **3 Cloud Monitoring Dashboards**
- **5 Log-based Metrics**
- **3 Alert Policies**

---

## 🔐 Security Considerations

### Service Account Permissions

The GitHub Actions service account needs these IAM roles:

- `roles/container.admin` - GKE management
- `roles/artifactregistry.admin` - Docker image push
- `roles/secretmanager.admin` - Secrets management
- `roles/pubsub.admin` - Pub/Sub topics
- `roles/bigquery.admin` - Analytics database
- `roles/storage.admin` - Evidence storage
- `roles/monitoring.admin` - Dashboards & alerts
- `roles/iam.serviceAccountAdmin` - Workload Identity

**Recommendation:** In production, use more granular roles instead of `roles/owner`

### Secrets Management

All secrets are stored in **GCP Secret Manager**, not in code:

```bash
# View secrets (value is redacted)
gcloud secrets list

# Access secret (requires permission)
gcloud secrets versions access latest --secret="github-token"
```

### API Keys

Retrieve API keys from Secret Manager:

```bash
# Get API keys
kubectl get secret security-patch-agent-api-keys \
  -n security-patch-agent \
  -o jsonpath='{.data.api-keys}' | base64 -d

# Or from Secret Manager
gcloud secrets versions access latest \
  --secret="security-patch-agent-api-keys"
```

---

## 🎯 Summary: Switching Projects

**For GitHub Actions users (simplest):**
1. Update `GCP_PROJECT_ID` and `GCP_SA_KEY` in GitHub Secrets
2. Run "Full Deployment" workflow
3. Done! (~15 minutes)

**For manual deployment:**
1. Create new GCP project
2. Update Terraform variables + backend bucket
3. Run `terraform apply`
4. Add secrets to Secret Manager
5. Run `kubectl apply -f deployment/k8s-manifests/`

**Cost:** ~$750/month per project

**Cleanup:** Run cleanup workflow or `./cleanup.sh` to delete all resources

---

## 📞 Troubleshooting

### Issue: "Permission denied" errors

**Solution:** Ensure service account has required IAM roles:
```bash
gcloud projects get-iam-policy YOUR-NEW-PROJECT-ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:github-actions@*"
```

### Issue: Terraform backend error

**Solution:** Create state bucket first:
```bash
gsutil mb -p YOUR-NEW-PROJECT-ID -l us-central1 \
  gs://YOUR-NEW-PROJECT-ID-terraform-state
```

### Issue: GKE cluster creation fails

**Solution:** Check quotas:
```bash
gcloud compute project-info describe --project=YOUR-NEW-PROJECT-ID
```

### Issue: Secrets not found

**Solution:** Add secrets to Secret Manager (see step 4 above)

---

## 🔗 Related Documentation

- [INSTALLATION.md](INSTALLATION.md) - Complete installation guide
- [README.md](README.md) - Project overview
- [cleanup.sh](cleanup.sh) - Cleanup script
- [infrastructure/terraform/](infrastructure/terraform/) - Terraform configuration

---

**Questions?** Contact kannavkunal@gmail.com
