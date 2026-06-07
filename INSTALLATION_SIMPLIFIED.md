# Security Patch Agent - Installation Guide

> **Complete setup guide using Terraform automation**

This guide shows you how to deploy the Security Patch Agent using Terraform and GitHub Actions. Most infrastructure is automated - you only need to do **5 manual setup steps**.

---

## 📋 Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [GCP Project Setup](#2-gcp-project-setup)
3. [Create Secrets (Manual)](#3-create-secrets-manual)
4. [Deploy Infrastructure (Terraform)](#4-deploy-infrastructure-terraform)
5. [Deploy Application (GitHub Actions)](#5-deploy-application-github-actions)
6. [Verification](#6-verification)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Prerequisites

### Install Required Tools

```bash
# macOS
brew install google-cloud-sdk kubectl terraform git jq

# Verify installations
gcloud --version
kubectl version --client
terraform --version
```

### Required Accounts

1. **Google Cloud Account** - https://cloud.google.com
2. **GitHub Account** - https://github.com
3. **Google AI Studio Account** (for Gemini API) - https://aistudio.google.com

---

## 2. GCP Project Setup

### Step 2.1: Create or Select Project

```bash
# Set project ID
export PROJECT_ID="security-patch-agent-gcp"

# Create new project (or use existing)
gcloud projects create $PROJECT_ID --name="Security Patch Agent"

# Set as active project
gcloud config set project $PROJECT_ID
```

### Step 2.2: Enable Required APIs

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

# Verify APIs enabled
gcloud services list --enabled | grep -E "(container|artifact|pubsub|bigquery)"
```

### Step 2.3: Authenticate

**Option A: Personal Account (Development)**
```bash
gcloud auth login
gcloud auth application-default login
```

**Option B: Service Account (Production)**
```bash
# Download service account key from Cloud Console
# Settings → IAM → Service Accounts → Create Key

gcloud auth activate-service-account \
  --key-file=/path/to/service-account-key.json
  
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
```

---

## 3. Create Secrets (Manual)

These secrets must be created **before** running Terraform.

### Step 3.1: Get GitHub Personal Access Token

1. Go to: https://github.com/settings/tokens
2. Click **"Generate new token (classic)"**
3. Set expiration: **90 days**
4. Select scopes:
   - ☑ `repo` (full control)
5. Generate and **save the token**

### Step 3.2: Get Gemini API Key

1. Go to: https://aistudio.google.com/apikey
2. Click **"Create API Key"**
3. Select project: `security-patch-agent-gcp`
4. **Save the API key**

### Step 3.3: Generate Webhook Secret

```bash
# Generate random 32-byte hex string
export WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "Webhook Secret: $WEBHOOK_SECRET"
# SAVE THIS - you'll need it for GitHub webhook configuration
```

### Step 3.4: Create Secrets in Secret Manager

```bash
# GitHub token
echo -n "ghp_YOUR_TOKEN_HERE" | gcloud secrets create github-token \
  --project=$PROJECT_ID \
  --data-file=- \
  --replication-policy="automatic"

# Gemini API key  
echo -n "YOUR_GEMINI_API_KEY" | gcloud secrets create gemini-api-key \
  --project=$PROJECT_ID \
  --data-file=- \
  --replication-policy="automatic"

# Webhook secret
echo -n "$WEBHOOK_SECRET" | gcloud secrets create github-webhook-secret \
  --project=$PROJECT_ID \
  --data-file=- \
  --replication-policy="automatic"

# Verify secrets created
gcloud secrets list --project=$PROJECT_ID
```

Expected output:
```
NAME                    CREATED
gemini-api-key         2026-06-07T...
github-token           2026-06-07T...
github-webhook-secret  2026-06-07T...
```

---

## 4. Deploy Infrastructure (Terraform)

### Step 4.1: Create Terraform State Bucket (Manual)

**IMPORTANT:** This bucket stores Terraform state and must exist before running `terraform init`.

```bash
# Create state bucket (globally unique name)
gsutil mb -p $PROJECT_ID \
  -c STANDARD \
  -l us-central1 \
  gs://${PROJECT_ID}-terraform-state

# Enable versioning (recommended)
gsutil versioning set on gs://${PROJECT_ID}-terraform-state

# Verify bucket created
gsutil ls -p $PROJECT_ID | grep terraform-state
```

### Step 4.2: Configure Terraform Backend

```bash
cd infrastructure/terraform

# Update backend.tf with your bucket name
cat > backend.tf << EOF
terraform {
  backend "gcs" {
    bucket = "${PROJECT_ID}-terraform-state"
    prefix = "security-patch-agent"
  }
}
