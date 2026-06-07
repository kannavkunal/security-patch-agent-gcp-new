#!/bin/bash
set -e

# Configuration
PROJECT_ID="compact-orb-498606-f9"
REGION="us-central1"
CLUSTER_NAME="code-vulnerability-scanner"
REPOSITORY_NAME="security-patch-agent"
IMAGE_NAME="api"

echo "================================================"
echo "Deploying Security Patch Agent to GKE"
echo "================================================"

# Step 1: Create Artifact Registry repository
echo "1. Creating Artifact Registry repository..."
gcloud artifacts repositories create ${REPOSITORY_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --description="Docker repository for Security Patch Agent" \
    --project=${PROJECT_ID} 2>/dev/null || echo "Repository already exists"

# Step 2: Configure Docker authentication
echo "2. Configuring Docker authentication..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Step 3: Build the Docker image
echo "3. Building Docker image..."
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY_NAME}/${IMAGE_NAME}:latest"
docker build -t ${IMAGE_TAG} .

# Step 4: Push the image
echo "4. Pushing Docker image to Artifact Registry..."
docker push ${IMAGE_TAG}

# Step 5: Get cluster credentials
echo "5. Getting GKE cluster credentials..."
gcloud container clusters get-credentials ${CLUSTER_NAME} \
    --region=${REGION} \
    --project=${PROJECT_ID}

# Step 6: Setup Istio
echo "6. Setting up Istio..."
bash setup-istio.sh

# Step 7: Setup Workload Identity
echo "7. Setting up Workload Identity..."
bash setup-workload-identity.sh

# Step 8: Deploy using Helm
echo "8. Deploying application using Helm..."
helm upgrade --install security-patch-agent ./helm/security-patch-agent \
    --create-namespace \
    --set image.tag=latest \
    --wait

# Step 9: Get Istio Ingress Gateway IP
echo "9. Getting Istio Ingress Gateway IP..."
INGRESS_HOST=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -n "$INGRESS_HOST" ]; then
    echo "Istio Ingress Gateway IP: $INGRESS_HOST"
else
    echo "Warning: Ingress Gateway IP not yet available"
fi

echo "================================================"
echo "Deployment complete!"
echo "================================================"
echo ""
echo "Access the API via Istio Ingress Gateway:"
if [ -n "$INGRESS_HOST" ]; then
    echo "  export INGRESS_HOST=$INGRESS_HOST"
    echo "  curl http://\$INGRESS_HOST/health"
else
    echo "  export INGRESS_HOST=\$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
    echo "  curl http://\$INGRESS_HOST/health"
fi
echo ""
echo "Check pod status (3 containers: app + envoy + fluent-bit):"
echo "  kubectl get pods -n security-patch-agent -l app.kubernetes.io/name=security-patch-agent"
echo ""
echo "View logs:"
echo "  kubectl logs -n security-patch-agent -l app.kubernetes.io/name=security-patch-agent -c security-patch-agent -f"
echo ""
echo "Check Istio sidecar injection:"
echo "  kubectl describe pod -n security-patch-agent -l app.kubernetes.io/name=security-patch-agent | grep -A 5 'Containers:'"
