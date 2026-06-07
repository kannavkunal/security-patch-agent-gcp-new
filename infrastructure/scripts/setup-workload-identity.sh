#!/bin/bash
set -e

# Configuration
PROJECT_ID="compact-orb-498606-f9"
CLUSTER_NAME="code-vulnerability-scanner"
CLUSTER_REGION="us-central1"
GSA_NAME="security-patch-agent"
GSA_EMAIL="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KSA_NAME="security-patch-agent-sa"
NAMESPACE="security-patch-agent"

echo "================================================"
echo "Setting up Workload Identity for Security Patch Agent"
echo "================================================"

# Enable required APIs
echo "1. Enabling required GCP APIs..."
gcloud services enable \
    container.googleapis.com \
    aiplatform.googleapis.com \
    artifactregistry.googleapis.com \
    --project=${PROJECT_ID}

# Create Google Service Account
echo "2. Creating Google Service Account: ${GSA_EMAIL}..."
gcloud iam service-accounts create ${GSA_NAME} \
    --display-name="Security Patch Agent Service Account" \
    --project=${PROJECT_ID} || echo "Service account already exists"

# Grant necessary IAM roles to the GSA
echo "3. Granting IAM roles to Google Service Account..."
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GSA_EMAIL}" \
    --role="roles/aiplatform.user" \
    --condition=None

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${GSA_EMAIL}" \
    --role="roles/artifactregistry.reader" \
    --condition=None

# Enable Workload Identity on the cluster (if not already enabled)
echo "4. Enabling Workload Identity on GKE cluster..."
gcloud container clusters update ${CLUSTER_NAME} \
    --region=${CLUSTER_REGION} \
    --workload-pool=${PROJECT_ID}.svc.id.goog \
    --project=${PROJECT_ID} || echo "Workload Identity already enabled"

# Bind the GSA to the KSA
echo "5. Binding Google Service Account to Kubernetes Service Account..."
gcloud iam service-accounts add-iam-policy-binding ${GSA_EMAIL} \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]" \
    --project=${PROJECT_ID}

echo "================================================"
echo "Workload Identity setup complete!"
echo "================================================"
echo ""
echo "Google Service Account: ${GSA_EMAIL}"
echo "Kubernetes Service Account: ${KSA_NAME}"
echo "Namespace: ${NAMESPACE}"
echo ""
echo "You can now deploy your application using the Helm chart."
