# Security Patch Agent - Complete Installation Guide

> **Complete end-to-end guide for deploying Security Patch Agent to Google Cloud Platform**

This guide walks you through deploying the Security Patch Agent from scratch, starting with creating a GCP account to having a fully functional security scanning system.

---

## 📋 Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [GCP Account & Project Setup](#2-gcp-account--project-setup)
3. [Configuration Files to Modify](#3-configuration-files-to-modify)
4. [Enable Required APIs](#4-enable-required-apis)
5. [Create Service Account & Permissions](#5-create-service-account--permissions)
6. [Setup GitHub Repository & Tokens](#6-setup-github-repository--tokens)
7. [GCP Infrastructure Setup](#7-gcp-infrastructure-setup)
8. [GKE Cluster Creation](#8-gke-cluster-creation)
9. [Build & Deploy Application](#9-build--deploy-application)
10. [Configure Secrets](#10-configure-secrets)
11. [Setup Monitoring](#11-setup-monitoring)
12. [Testing the Deployment](#12-testing-the-deployment)
13. [Configure GitHub Webhooks (Optional)](#13-configure-github-webhooks-optional)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Prerequisites

### 1.1 Install Required Tools

**IMPORTANT:** Install these tools BEFORE proceeding with deployment.

#### **Step 1: Install gcloud CLI (Google Cloud SDK)**

**macOS:**
```bash
brew install google-cloud-sdk

# Initialize gcloud
gcloud init
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y google-cloud-sdk

# Initialize gcloud
gcloud init
```

**Windows:**
Download from: https://cloud.google.com/sdk/docs/install

**Verify gcloud installation:**
```bash
gcloud --version
# Should output: Google Cloud SDK 4xx.x.x
```

#### **Step 2: Install Other Required Tools**

```bash
# macOS
brew install kubectl docker jq git terraform

# Linux (Ubuntu/Debian)
sudo apt-get install -y kubectl docker.io jq git

# Install Terraform (Linux)
wget https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip
unzip terraform_1.7.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Verify all installations
kubectl version --client
docker --version
jq --version
git --version
terraform --version
```

### Required Accounts

1. **Google Cloud Account**: https://cloud.google.com
2. **GitHub Account**: https://github.com
3. **Google AI Studio Account** (for Gemini API): https://aistudio.google.com

---

## 🔑 Authentication Guide

**Prerequisites:** 
- ✅ gcloud CLI installed (Section 1.1)
- ✅ Google Cloud account created (Section 2.1)

**Now authenticate to use gcloud commands:**

### Required: Personal Google Account Authentication

```bash
# Step 1: Login with your Google account (REQUIRED - do this first!)
gcloud auth login
```

**What this does:**
- Opens browser for Google login
- Authenticates YOU (as a person)
- Stores credentials locally (~/.config/gcloud/)

**What you can do after authentication:**
- ✅ Create projects
- ✅ Enable APIs
- ✅ Run Terraform
- ✅ Manage GKE clusters
- ✅ Run kubectl commands
- ✅ Deploy applications

### Optional: Service Account (for automation)

```bash
# Step 2: Create service account key (OPTIONAL)
gcloud iam service-accounts keys create ~/gcp-sa-key.json --iam-account=...
gcloud auth activate-service-account --key-file=~/gcp-sa-key.json
```

This authenticates SCRIPTS/CI-CD and is only needed for:
- ⚠️ Automated deployments
- ⚠️ CI/CD pipelines
- ⚠️ Scripts that can't use browser login

**For this installation guide:** Use your personal account (`gcloud auth login`). Service account is optional.

---

## 2. GCP Account & Project Setup

### Step 2.1: Create GCP Account

1. Go to https://cloud.google.com
2. Click **"Get started for free"**
3. Sign in with your Google account
4. Complete billing setup (new users get $300 free credit for 90 days)

### Step 2.2: Authenticate with Google Account

**IMPORTANT:** First, authenticate with your personal Google account:

```bash
# Login to GCP with your Google account (opens browser)
gcloud auth login
```

This will:
1. Open your browser for authentication
2. Ask you to select your Google account
3. Grant gcloud CLI permission to manage GCP resources
4. Save credentials locally

**Note:** This is different from service account authentication (covered later). `gcloud auth login` uses your personal Google account for administrative tasks.

### Step 2.3: Create New Project

```bash
# Set variables (customize these)
export PROJECT_ID="security-patch-agent-$(date +%s)"
export REGION="us-central1"
export ZONE="us-central1-a"

# Create project
gcloud projects create $PROJECT_ID --name="Security Patch Agent"

# Set default project
gcloud config set project $PROJECT_ID

# Link billing account (find your billing account ID first)
gcloud billing accounts list
export BILLING_ACCOUNT_ID="YOUR_BILLING_ACCOUNT_ID"
gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT_ID

# Set default region and zone
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

# Verify project setup
gcloud config list
```

**Save these values** - you'll need them throughout the installation:
- `PROJECT_ID`: Your GCP project ID
- `REGION`: us-central1 (or your preferred region)
- `ZONE`: us-central1-a (or your preferred zone)

---

## 2a. Service Account Authentication (Optional - For Local kubectl)

**When to use this:** If you want to run kubectl commands from your local machine to manage the GKE cluster.

**Authentication Methods:**
- **Personal Account** (`gcloud auth login`) - ✅ Already done in Step 2.2
  - Used for: gcloud commands, Terraform, general GCP management
  - Good for: Interactive use, development
  
- **Service Account** (this section) - ⚠️ Optional
  - Used for: Automated kubectl access, CI/CD pipelines
  - Good for: Scripts that need kubectl without browser login
  - **Not required** if using `gcloud auth login` + `gcloud container clusters get-credentials`

**Skip this section if:** You're fine using your personal account for kubectl commands.

### Step 2a.1: Download Service Account Key (Optional)

```bash
# Create a service account (if not already created)
gcloud iam service-accounts create deployment-manager \
  --display-name="Deployment Manager" \
  --project=$PROJECT_ID

# Grant necessary roles
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:deployment-manager@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:deployment-manager@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# Download service account key
gcloud iam service-accounts keys create ~/gcp-sa-key.json \
  --iam-account=deployment-manager@$PROJECT_ID.iam.gserviceaccount.com

# Activate service account
gcloud auth activate-service-account --key-file=~/gcp-sa-key.json
```

### Step 2a.2: Get GKE Cluster Credentials (Two Options)

**Option A: Using Personal Account (Simpler)**

```bash
# Already authenticated? Just get cluster credentials
gcloud container clusters get-credentials code-vulnerability-scanner \
  --region=us-central1 \
  --project=$PROJECT_ID

# Verify kubectl access (use --insecure-skip-tls-verify for certificate issues)
kubectl get pods -n security-patch-agent --insecure-skip-tls-verify
```

**Option B: Using Service Account (For Automation)**

If you created a service account key in Step 2a.1:

```bash
# Activate service account (instead of gcloud auth login)
gcloud auth activate-service-account --key-file=~/gcp-sa-key.json

# Get cluster credentials
gcloud container clusters get-credentials code-vulnerability-scanner \
  --region=us-central1 \
  --project=$PROJECT_ID

# Verify kubectl access
kubectl get pods -n security-patch-agent --insecure-skip-tls-verify
```

### Step 2a.3: Test kubectl Commands

```bash
# List namespaces
kubectl get namespaces --insecure-skip-tls-verify

# List services
kubectl get svc -n security-patch-agent --insecure-skip-tls-verify

# List jobs
kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify

# View pod logs
kubectl logs -n security-patch-agent -l app=security-patch-agent --insecure-skip-tls-verify --tail=50

# Get secret (API keys)
kubectl get secret security-patch-agent-api-keys -n security-patch-agent --insecure-skip-tls-verify -o jsonpath='{.data.api-keys}' | base64 -d
```

**Important:** Keep `~/gcp-sa-key.json` secure and add it to `.gitignore`. Never commit service account keys to Git.

---

## 3. Configuration Files to Modify

Before deploying, you need to update several configuration files with your project-specific values. Here's a comprehensive list:

### 📝 Files That MUST Be Modified

#### 1. **infrastructure/terraform/variables.tf**

Replace default values with your settings:

```bash
# Edit the file
vi infrastructure/terraform/variables.tf

# Update these variables:
variable "project_id" {
  default     = "YOUR_PROJECT_ID"  # Change this
}

variable "alert_email" {
  default     = "YOUR_EMAIL@example.com"  # Change this
}

variable "whitelisted_ips" {
  default     = ["YOUR_IP_ADDRESS/32"]  # Change this
}
```

**What to change**:
- `project_id`: Your GCP project ID (e.g., `security-patch-agent-1234567890`)
- `alert_email`: Your email for monitoring alerts
- `whitelisted_ips`: Your office/VPN IP addresses for API access

---

#### 2. **deployment/k8s-manifests/02-serviceaccount.yaml**

Update service account annotation:

```bash
# Edit the file
vi deployment/k8s-manifests/02-serviceaccount.yaml

# Find and replace:
annotations:
  iam.gke.io/gcp-service-account: security-patch-agent@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

**What to change**:
- Replace `compact-orb-498606-f9` with your `PROJECT_ID`

---

#### 3. **deployment/k8s-manifests/05-deployment.yaml**

Update environment variables:

```bash
# Edit the file
vi deployment/k8s-manifests/05-deployment.yaml

# Update these env vars:
- name: GCP_PROJECT_ID
  value: "YOUR_PROJECT_ID"
- name: GCS_BUCKET
  value: "security-patch-evidence-YOUR_PROJECT_ID"
```

**What to change**:
- `GCP_PROJECT_ID`: Your project ID
- `GCS_BUCKET`: Your evidence bucket name (must be globally unique)

---

#### 4. **test_e2e_complete.sh**

Update API URL:

```bash
# Edit the file
vi test_e2e_complete.sh

# Change line 4:
API_URL="http://YOUR_LOAD_BALANCER_IP"
```

**What to change**:
- Replace `34.171.214.25` with your LoadBalancer external IP (get this after deployment)

---

#### 5. **test_review_mode.sh**

Update API URL and project ID:

```bash
# Edit the file
vi test_review_mode.sh

# Update:
API_URL="http://YOUR_LOAD_BALANCER_IP"
PROJECT_ID="YOUR_PROJECT_ID"
```

---

#### 6. **setup_monitoring.sh**

Update project ID:

```bash
# Edit the file
vi setup_monitoring.sh

# Change line 4:
PROJECT_ID="YOUR_PROJECT_ID"
```

---

#### 7. **infrastructure/scripts/deploy.sh**

Update deployment script variables:

```bash
# Edit the file
vi infrastructure/scripts/deploy.sh

# Update lines 5-8:
PROJECT_ID="YOUR_PROJECT_ID"
REGION="YOUR_REGION"
CLUSTER_NAME="YOUR_CLUSTER_NAME"
REPOSITORY_NAME="YOUR_REGISTRY_NAME"
```

---

### 📝 Files You Can Keep As-Is

These files use environment variables or runtime configuration:

- ✅ **app/main.py** - Reads from environment variables
- ✅ **app/config.py** - Uses env vars from Kubernetes
- ✅ **requirements.txt** - No changes needed
- ✅ **app/Dockerfile** - Generic, no project-specific values

---

### 🔧 Quick Find & Replace Script

Use this script to automatically replace values in all files:

```bash
# Save your configuration
export NEW_PROJECT_ID="your-project-id-here"
export NEW_EMAIL="your-email@example.com"
export NEW_IP="1.2.3.4"

# Run find & replace
find . -type f \( -name "*.yaml" -o -name "*.tf" -o -name "*.sh" \) \
  -not -path "./venv/*" \
  -not -path "./.git/*" \
  -exec sed -i.bak \
    -e "s/compact-orb-498606-f9/${NEW_PROJECT_ID}/g" \
    -e "s/kunal@example.com/${NEW_EMAIL}/g" \
    -e "s/199.167.52.5/${NEW_IP}/g" \
    {} +

# Remove backup files
find . -name "*.bak" -delete

echo "✅ Configuration updated!"
echo "Review changes: git diff"
```

---

### ✅ Verification Checklist

Before proceeding to deployment, verify:

- [ ] `PROJECT_ID` updated in all Terraform files
- [ ] `PROJECT_ID` updated in all Kubernetes manifests
- [ ] Service account email matches your project
- [ ] Email address set for monitoring alerts
- [ ] Test scripts point to correct API URL
- [ ] GCS bucket name is globally unique
- [ ] All `.bak` backup files removed

**Tip**: Use `grep -r "compact-orb-498606-f9" .` to find any missed references to the old project ID.

---

## 4. Enable Required APIs

Enable all necessary GCP APIs for the project:

```bash
# Enable APIs (this may take 2-3 minutes)
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

# Verify APIs are enabled
gcloud services list --enabled | grep -E "(container|artifact|pubsub|bigquery|storage|secret)"
```

Expected output should show all services enabled:
```
bigquery.googleapis.com
container.googleapis.com
artifactregistry.googleapis.com
pubsub.googleapis.com
secretmanager.googleapis.com
storage.googleapis.com
```

---

## 4. Create Service Account & Permissions

### Step 4.1: Create GCP Service Account

```bash
# Create service account
gcloud iam service-accounts create security-patch-agent \
  --display-name="Security Patch Agent Service Account" \
  --description="Service account for security vulnerability scanning and remediation"

# Get service account email
export SA_EMAIL="security-patch-agent@${PROJECT_ID}.iam.gserviceaccount.com"
echo "Service Account Email: $SA_EMAIL"
```

### Step 4.2: Grant IAM Permissions

```bash
# Grant necessary roles to service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/pubsub.editor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/aiplatform.user"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/logging.logWriter"

# Verify permissions
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${SA_EMAIL}"
```

### Step 4.3: Create Service Account Key (for local development)

```bash
# Create key file
gcloud iam service-accounts keys create ~/security-patch-agent-key.json \
  --iam-account=$SA_EMAIL

# Set environment variable
export GOOGLE_APPLICATION_CREDENTIALS=~/security-patch-agent-key.json

echo "Service account key saved to: ~/security-patch-agent-key.json"
echo "KEEP THIS FILE SECURE - DO NOT COMMIT TO GIT"
```

---

## 5. Setup GitHub Repository & Tokens

### Step 5.1: Fork or Clone Repository

```bash
# Option A: Clone the repository
git clone https://github.com/kannavkunal/security-patch-agent.git
cd security-patch-agent

# Option B: Fork on GitHub, then clone your fork
# Go to https://github.com/kannavkunal/security-patch-agent
# Click "Fork" button
# Then clone:
git clone https://github.com/YOUR_USERNAME/security-patch-agent.git
cd security-patch-agent
```

### Step 5.2: Create GitHub Personal Access Token

1. Go to GitHub Settings: https://github.com/settings/tokens
2. Click **"Generate new token (classic)"**
3. Give it a descriptive name: `security-patch-agent`
4. Set expiration: **No expiration** (or 1 year)
5. Select scopes:
   - ✅ **repo** (all)
   - ✅ **workflow**
   - ✅ **write:packages**
6. Click **"Generate token"**
7. **Copy the token immediately** - you won't see it again!

```bash
# Save token as environment variable
export GITHUB_TOKEN="ghp_YOUR_TOKEN_HERE"
echo $GITHUB_TOKEN  # Verify it's set
```

### Step 5.3: Get Gemini API Key

1. Go to Google AI Studio: https://aistudio.google.com/app/apikey
2. Click **"Create API Key"**
3. Select your GCP project
4. Copy the API key

```bash
# Save Gemini API key
export GEMINI_API_KEY="YOUR_GEMINI_API_KEY_HERE"
echo $GEMINI_API_KEY  # Verify it's set
```

### Step 5.4: Generate HMAC Secret for Webhooks

```bash
# Generate random HMAC secret (256-bit)
export WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "Webhook Secret: $WEBHOOK_SECRET"
# Save this - you'll need it when configuring GitHub webhooks
```

---

## 6. GCP Infrastructure Setup

### Step 6.1: Create BigQuery Dataset

```bash
# Create dataset for scan logs
bq --location=$REGION mk \
  --dataset \
  --description="Security scan analytics" \
  ${PROJECT_ID}:security_scans

# Create scans table
bq mk --table \
  ${PROJECT_ID}:security_scans.scans \
  scan_id:STRING,timestamp:TIMESTAMP,repo_name:STRING,repo_owner:STRING,scan_mode:STRING,trigger_type:STRING,llm_model_used:STRING,vulnerabilities_found:INTEGER,fixes_applied:INTEGER,pr_number:INTEGER,pr_url:STRING,evidence_path:STRING,findings_summary:JSON,patches_summary:JSON

# Verify table created
bq show ${PROJECT_ID}:security_scans.scans
```

### Step 6.2: Create GCS Bucket for Evidence

```bash
# Create bucket (name must be globally unique)
export BUCKET_NAME="security-patch-evidence-${PROJECT_ID}"
gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://${BUCKET_NAME}/

# Enable versioning
gsutil versioning set on gs://${BUCKET_NAME}/

# Set lifecycle policy (delete old evidence after 90 days)
cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF
gsutil lifecycle set /tmp/lifecycle.json gs://${BUCKET_NAME}/

# Verify bucket
gsutil ls -L gs://${BUCKET_NAME}/
```

### Step 6.3: Create Pub/Sub Topic & Subscription

```bash
# Create topic for scan events
gcloud pubsub topics create scan-events \
  --message-retention-duration=7d

# Create subscription for workers
gcloud pubsub subscriptions create scan-events-sub \
  --topic=scan-events \
  --ack-deadline=600 \
  --message-retention-duration=7d \
  --expiration-period=never

# Verify
gcloud pubsub topics list
gcloud pubsub subscriptions list
```

### Step 6.4: Store Secrets in Secret Manager

```bash
# Store GitHub token
echo -n $GITHUB_TOKEN | gcloud secrets create github-token \
  --data-file=- \
  --replication-policy="automatic"

# Store Gemini API key
echo -n $GEMINI_API_KEY | gcloud secrets create gemini-api-key \
  --data-file=- \
  --replication-policy="automatic"

# Store webhook secret
echo -n $WEBHOOK_SECRET | gcloud secrets create webhook-secret \
  --data-file=- \
  --replication-policy="automatic"

# Grant service account access to secrets
for SECRET in github-token gemini-api-key webhook-secret; do
  gcloud secrets add-iam-policy-binding $SECRET \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/secretmanager.secretAccessor"
done

# Verify secrets
gcloud secrets list
```

---

## 7. GKE Cluster Creation

### Step 7.1: Create GKE Cluster

```bash
# Create GKE cluster (this takes 5-10 minutes)
gcloud container clusters create code-vulnerability-scanner \
  --region=$REGION \
  --num-nodes=2 \
  --machine-type=e2-standard-4 \
  --disk-size=50 \
  --disk-type=pd-standard \
  --enable-autoscaling \
  --min-nodes=1 \
  --max-nodes=5 \
  --enable-autorepair \
  --enable-autoupgrade \
  --workload-pool=${PROJECT_ID}.svc.id.goog \
  --enable-ip-alias \
  --network=default \
  --subnetwork=default \
  --logging=SYSTEM,WORKLOAD \
  --monitoring=SYSTEM \
  --addons=HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver

# Get cluster credentials
gcloud container clusters get-credentials code-vulnerability-scanner --region=$REGION

# Verify cluster
kubectl cluster-info
kubectl get nodes
```

Expected output:
```
NAME                                                  STATUS   ROLES    AGE   VERSION
gke-code-vulnerability-scanner-default-pool-xxx       Ready    <none>   2m    v1.28.x
gke-code-vulnerability-scanner-default-pool-yyy       Ready    <none>   2m    v1.28.x
```

### Step 7.2: Setup Workload Identity

```bash
# Create Kubernetes namespace
kubectl create namespace security-patch-agent

# Create Kubernetes service account
kubectl create serviceaccount security-patch-agent-sa -n security-patch-agent

# Bind Kubernetes SA to GCP SA (Workload Identity)
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[security-patch-agent/security-patch-agent-sa]"

# Annotate Kubernetes service account
kubectl annotate serviceaccount security-patch-agent-sa \
  -n security-patch-agent \
  iam.gke.io/gcp-service-account=$SA_EMAIL

# Verify
kubectl get serviceaccount security-patch-agent-sa -n security-patch-agent -o yaml | grep iam.gke.io
```

### Step 7.3: Create RBAC Permissions

```bash
# Apply RBAC for Kubernetes Jobs
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: job-creator
  namespace: security-patch-agent
rules:
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: job-creator-binding
  namespace: security-patch-agent
subjects:
- kind: ServiceAccount
  name: security-patch-agent-sa
  namespace: security-patch-agent
roleRef:
  kind: Role
  name: job-creator
  apiGroup: rbac.authorization.k8s.io
EOF

# Verify RBAC
kubectl get role,rolebinding -n security-patch-agent
```

---

## 8. Build & Deploy Application

### Step 8.1: Create Artifact Registry

```bash
# Create Docker repository
gcloud artifacts repositories create security-patch-agent \
  --repository-format=docker \
  --location=$REGION \
  --description="Docker images for Security Patch Agent"

# Configure Docker authentication
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Verify repository
gcloud artifacts repositories list --location=$REGION
```

### Step 8.2: Build Docker Image

```bash
# Navigate to app directory
cd app/

# Build image
export IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/security-patch-agent/api:latest"
docker build -t $IMAGE_TAG .

# Verify image built
docker images | grep security-patch-agent
```

### Step 8.3: Push to Artifact Registry

```bash
# Push image
docker push $IMAGE_TAG

# Verify push
gcloud artifacts docker images list ${REGION}-docker.pkg.dev/${PROJECT_ID}/security-patch-agent
```

### Step 8.4: Deploy to GKE

```bash
# Go back to root directory
cd ..

# Update deployment manifests with your project details
export SA_EMAIL="security-patch-agent@${PROJECT_ID}.iam.gserviceaccount.com"

# Update service account annotation
sed -i.bak "s/compact-orb-498606-f9/${PROJECT_ID}/g" deployment/k8s-manifests/02-serviceaccount.yaml

# Apply all manifests
kubectl apply -f deployment/k8s-manifests/01-namespace.yaml
kubectl apply -f deployment/k8s-manifests/02-serviceaccount.yaml
kubectl apply -f deployment/k8s-manifests/04-configmap.yaml

# Update deployment with your image
cat > deployment/k8s-manifests/05-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: security-patch-agent
  namespace: security-patch-agent
spec:
  replicas: 2
  selector:
    matchLabels:
      app: security-patch-agent
  template:
    metadata:
      labels:
        app: security-patch-agent
    spec:
      serviceAccountName: security-patch-agent-sa
      containers:
      - name: api
        image: ${IMAGE_TAG}
        ports:
        - containerPort: 8080
        env:
        - name: GCP_PROJECT_ID
          value: "${PROJECT_ID}"
        - name: GCP_REGION
          value: "${REGION}"
        - name: PUBSUB_TOPIC
          value: "scan-events"
        - name: BIGQUERY_DATASET
          value: "security_scans"
        - name: BIGQUERY_TABLE
          value: "scans"
        - name: GCS_BUCKET
          value: "${BUCKET_NAME}"
        - name: K8S_NAMESPACE
          value: "security-patch-agent"
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
EOF

# Apply deployment
kubectl apply -f deployment/k8s-manifests/05-deployment.yaml

# Create service
cat > deployment/k8s-manifests/06-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: security-patch-agent
  namespace: security-patch-agent
spec:
  type: LoadBalancer
  selector:
    app: security-patch-agent
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
EOF

kubectl apply -f deployment/k8s-manifests/06-service.yaml

# Wait for deployment
kubectl rollout status deployment/security-patch-agent -n security-patch-agent

# Get pods
kubectl get pods -n security-patch-agent
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS   AGE
security-patch-agent-xxxxx-yyyyy        1/1     Running   0          2m
security-patch-agent-xxxxx-zzzzz        1/1     Running   0          2m
```

### Step 8.5: Get External IP

```bash
# Wait for external IP (this may take 2-3 minutes)
kubectl get service security-patch-agent -n security-patch-agent -w

# Once EXTERNAL-IP appears (not <pending>), press Ctrl+C
export API_URL=$(kubectl get service security-patch-agent -n security-patch-agent -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "API URL: http://$API_URL"

# Test health endpoint
curl http://$API_URL/health
```

Expected response:
```json
{
  "status": "healthy",
  "service": "security-patch-agent",
  "version": "1.0.0"
}
```

---

## 9. Configure Secrets

### Step 9.1: Create Kubernetes Secret for API Keys (Optional)

```bash
# Generate API keys for authenticating API requests
export API_KEY_PRIMARY=$(openssl rand -hex 32)
export API_KEY_SECONDARY=$(openssl rand -hex 32)

# Create Kubernetes secret
kubectl create secret generic security-patch-agent-api-keys \
  --from-literal=api-keys="${API_KEY_PRIMARY},${API_KEY_SECONDARY}" \
  -n security-patch-agent

# Save API keys securely
echo "Primary API Key: $API_KEY_PRIMARY" >> ~/security-patch-agent-keys.txt
echo "Secondary API Key: $API_KEY_SECONDARY" >> ~/security-patch-agent-keys.txt
echo "Webhook Secret: $WEBHOOK_SECRET" >> ~/security-patch-agent-keys.txt

cat ~/security-patch-agent-keys.txt
```

---

## 10. Setup Monitoring

### Step 10.1: Create Log-Based Metrics

```bash
# Run monitoring setup script
chmod +x setup_monitoring.sh
./setup_monitoring.sh
```

Or manually create metrics:

```bash
# Scan success metric
gcloud logging metrics create scan_success \
  --description="Count of successful vulnerability scans" \
  --log-filter='resource.type="k8s_container"
resource.labels.namespace_name="security-patch-agent"
jsonPayload.message=~"Scan completed successfully"'

# Scan failure metric
gcloud logging metrics create scan_failures \
  --description="Count of failed vulnerability scans" \
  --log-filter='resource.type="k8s_container"
resource.labels.namespace_name="security-patch-agent"
severity="ERROR"
jsonPayload.message=~"Scan failed"'

# PRs created metric
gcloud logging metrics create prs_created \
  --description="Count of pull requests created" \
  --log-filter='resource.type="k8s_container"
resource.labels.namespace_name="security-patch-agent"
jsonPayload.message=~"Created pull request"'

# Verify metrics
gcloud logging metrics list | grep -E "(scan_success|scan_failures|prs_created)"
```

### Step 10.2: Create Dashboards

```bash
# Open GCP Console
echo "Open this URL to create dashboards:"
echo "https://console.cloud.google.com/monitoring/dashboards?project=${PROJECT_ID}"

# Dashboards are created automatically by setup_monitoring.sh
# Or manually import from infrastructure/dashboards/
```

### Step 10.3: Create Alert Policies

```bash
# High scan failure rate alert
gcloud alpha monitoring policies create \
  --notification-channels=CHANNEL_ID \
  --display-name="High Scan Failure Rate" \
  --condition-display-name="Scan failures > 5 in 10 min" \
  --condition-threshold-value=5 \
  --condition-threshold-duration=600s \
  --condition-filter='resource.type="k8s_container" AND metric.type="logging.googleapis.com/user/scan_failures"'

echo "Setup email notification channels in GCP Console:"
echo "https://console.cloud.google.com/monitoring/alerting/notifications?project=${PROJECT_ID}"
```

---

## 11. Testing the Deployment

### Step 11.1: Test Health Endpoint

```bash
curl http://$API_URL/health | jq .
```

Expected:
```json
{
  "status": "healthy",
  "service": "security-patch-agent",
  "version": "1.0.0",
  "timestamp": "2026-06-06T12:00:00Z"
}
```

### Step 11.2: Test PATCH Mode (Full Repo Scan)

```bash
# Trigger scan on a test repository
curl -X POST http://$API_URL/scan \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY_PRIMARY" \
  -d '{
    "repo_url": "https://github.com/kannavkunal/vulnerable-python-api",
    "mode": "patch",
    "branch": "main"
  }' | jq .
```

Expected response:
```json
{
  "scan_id": "scan-abc123def456",
  "status": "queued",
  "message": "Scan job created successfully",
  "job_name": "scan-abc123"
}
```

### Step 11.3: Monitor Scan Progress

```bash
# Get scan ID from previous response
export SCAN_ID="scan-abc123def456"

# Watch Kubernetes job
kubectl get jobs -n security-patch-agent -w

# View job logs
export JOB_NAME=$(kubectl get jobs -n security-patch-agent --sort-by=.metadata.creationTimestamp -o name | tail -1 | cut -d/ -f2)
kubectl logs -n security-patch-agent job/$JOB_NAME -f

# Query scan status from API
curl http://$API_URL/scans/$SCAN_ID | jq .
```

### Step 11.4: Verify Results

```bash
# Check BigQuery for scan data
bq query --use_legacy_sql=false "
SELECT 
  scan_id,
  repo_name,
  scan_mode,
  vulnerabilities_found,
  fixes_applied,
  pr_url
FROM \`${PROJECT_ID}.security_scans.scans\`
ORDER BY timestamp DESC
LIMIT 5
"

# Check GCS for evidence files
gsutil ls gs://${BUCKET_NAME}/

# View PR created
echo "Check GitHub PR: https://github.com/YOUR_USERNAME/vulnerable-python-api/pulls"
```

### Step 11.5: Run E2E Tests

```bash
# Run comprehensive test suite
chmod +x test_e2e_complete.sh

# Update API URL in script
sed -i.bak "s|http://34.171.214.25|http://$API_URL|g" test_e2e_complete.sh

# Run tests
./test_e2e_complete.sh
```

---

## 12. Configure GitHub Webhooks (Optional)

To enable automatic PR scanning (REVIEW mode), configure GitHub webhooks:

### Step 12.1: Create Webhook in GitHub Repository

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Webhooks** → **Add webhook**
3. Configure webhook:
   - **Payload URL**: `http://$API_URL/webhook/github`
   - **Content type**: `application/json`
   - **Secret**: Use the `$WEBHOOK_SECRET` from earlier
   - **Which events?**: Select **"Let me select individual events"**
     - ✅ Pull requests
     - ✅ Pull request reviews
   - ✅ **Active**
4. Click **Add webhook**

### Step 12.2: Test Webhook

```bash
# Create a test PR in your repository
# The webhook should trigger automatically

# Check webhook deliveries in GitHub
# Settings → Webhooks → Recent Deliveries

# Monitor logs
kubectl logs -n security-patch-agent -l app=security-patch-agent -f | grep webhook
```

---

## 13. Troubleshooting

### Issue 1: Pods not starting

```bash
# Check pod status
kubectl get pods -n security-patch-agent

# Describe pod for errors
kubectl describe pod -n security-patch-agent <POD_NAME>

# Check logs
kubectl logs -n security-patch-agent <POD_NAME>

# Common issues:
# - Image pull errors: Verify Artifact Registry permissions
# - CrashLoopBackOff: Check application logs for errors
# - Pending: Check node resources (kubectl describe node)
```

### Issue 2: Cannot access API via LoadBalancer

```bash
# Verify service
kubectl get svc -n security-patch-agent

# Check firewall rules
gcloud compute firewall-rules list | grep default-allow

# Create firewall rule if needed
gcloud compute firewall-rules create allow-lb-health-checks \
  --network=default \
  --action=allow \
  --direction=ingress \
  --source-ranges=0.0.0.0/0 \
  --rules=tcp:8080

# Use port-forward as temporary workaround
kubectl port-forward -n security-patch-agent svc/security-patch-agent 8080:80
curl http://localhost:8080/health
```

### Issue 3: Scans failing with "Permission denied"

```bash
# Verify Workload Identity binding
gcloud iam service-accounts get-iam-policy $SA_EMAIL

# Re-bind if needed
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:${PROJECT_ID}.svc.id.goog[security-patch-agent/security-patch-agent-sa]"

# Verify secret access
gcloud secrets get-iam-policy github-token
```

### Issue 4: Jobs not creating

```bash
# Check RBAC permissions
kubectl auth can-i create jobs --as=system:serviceaccount:security-patch-agent:security-patch-agent-sa -n security-patch-agent

# Should return "yes" - if not, reapply RBAC:
kubectl apply -f deployment/k8s-manifests/02-serviceaccount.yaml
```

### Issue 5: No data in BigQuery

```bash
# Check if table exists
bq show ${PROJECT_ID}:security_scans.scans

# Verify service account has BigQuery permissions
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${SA_EMAIL}" | grep bigquery

# Check application logs for BigQuery errors
kubectl logs -n security-patch-agent -l app=security-patch-agent | grep -i bigquery
```

### Issue 6: Gemini API errors

```bash
# Verify API key in Secret Manager
gcloud secrets versions access latest --secret=gemini-api-key

# Check quota limits
gcloud alpha services quota list --service=aiplatform.googleapis.com

# Test Gemini API directly
curl -H "Content-Type: application/json" \
  -d '{"contents":[{"parts":[{"text":"Hello"}]}]}' \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro-latest:generateContent?key=$GEMINI_API_KEY"
```

---

## 🎉 Installation Complete!

Your Security Patch Agent is now fully deployed and operational!

### Quick Reference

**API Endpoint**: `http://$API_URL`

**Trigger PATCH scan**:
```bash
curl -X POST http://$API_URL/scan \
  -H "Content-Type: application/json" \
  -d '{"repo_url": "https://github.com/user/repo", "mode": "patch", "branch": "main"}'
```

**Query scans**:
```bash
curl http://$API_URL/scans?limit=10 | jq .
```

**View dashboards**:
- https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID

**Check logs**:
```bash
kubectl logs -n security-patch-agent -l app=security-patch-agent -f
```

---

## 📚 Next Steps

1. **Configure GitHub webhooks** for automatic PR scanning
2. **Setup monitoring alerts** for Slack/Email notifications
3. **Create custom Semgrep rules** for your organization
4. **Review PRD.md** for feature roadmap
5. **Read TESTING_GUIDE.md** for comprehensive testing procedures

---

## 🆘 Support

- **Documentation**: See README.md, PRD.md, TESTING_GUIDE.md
- **Issues**: https://github.com/kannavkunal/security-patch-agent/issues
- **Email**: kannavkunal@gmail.com

**Built for Tessera 2026** | **Powered by Google Gemini 2.5 Pro**
