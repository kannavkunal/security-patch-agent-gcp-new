#!/bin/bash
set -e

PROJECT_ID="compact-orb-498606-f9"
REGION="us-central1"
CLUSTER_NAME="code-vulnerability-scanner"
REPOSITORY_NAME="security-patch-agent"
IMAGE_NAME="api"

echo "================================================"
echo "Simple Deployment - GCP Native (No Istio)"
echo "================================================"
echo ""

# Step 1: Create Artifact Registry repository
echo "1. Creating Artifact Registry repository..."
gcloud artifacts repositories create ${REPOSITORY_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Docker repository for Security Patch Agent" \
    --project=${PROJECT_ID} 2>/dev/null || echo "Repository already exists"

# Step 2: Configure Docker
echo "2. Configuring Docker authentication..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Step 3: Build image
echo "3. Building Docker image..."
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}/${IMAGE_NAME}:latest"
docker build -t ${IMAGE_TAG} .

# Step 4: Push image
echo "4. Pushing Docker image..."
docker push ${IMAGE_TAG}

# Step 5: Update kubeconfig (with retries)
echo "5. Getting cluster credentials..."
for i in {1..3}; do
    gcloud container clusters get-credentials ${CLUSTER_NAME} \
        --region=${REGION} \
        --project=${PROJECT_ID} && break || sleep 5
done

# Step 6: Setup Workload Identity
echo "6. Setting up Workload Identity..."
bash setup-workload-identity.sh

# Step 7: Deploy with Helm (Istio disabled for now)
echo "7. Deploying with Helm (GCP LoadBalancer)..."
helm upgrade --install security-patch-agent ./helm/security-patch-agent \
    --create-namespace \
    --set istio.enabled=false \
    --set service.type=LoadBalancer \
    --set image.tag=latest \
    --wait \
    --timeout=10m

# Step 8: Get service IP
echo "8. Waiting for LoadBalancer IP..."
sleep 30

SERVICE_IP=$(kubectl get svc security-patch-agent -n security-patch-agent -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

echo ""
echo "================================================"
echo "Deployment Complete!"
echo "================================================"
echo ""
if [ "$SERVICE_IP" != "pending" ]; then
    echo "🌐 API Endpoint: http://$SERVICE_IP"
    echo ""
    echo "Test with:"
    echo "  curl http://$SERVICE_IP/health"
else
    echo "⏳ LoadBalancer IP pending..."
    echo "Check with: kubectl get svc security-patch-agent -n security-patch-agent"
fi
echo ""
echo "View pods:"
echo "  kubectl get pods -n security-patch-agent"
echo ""
