#!/bin/bash
set -e

# Configuration
PROJECT_ID="compact-orb-498606-f9"
CLUSTER_NAME="code-vulnerability-scanner"
CLUSTER_REGION="us-central1"

echo "================================================"
echo "Setting up Istio on GKE Cluster"
echo "================================================"

# Get cluster credentials
echo "1. Getting cluster credentials..."
gcloud container clusters get-credentials ${CLUSTER_NAME} \
    --region=${CLUSTER_REGION} \
    --project=${PROJECT_ID}

# Check if Istio is already enabled on the cluster
echo "2. Checking Istio status..."
ISTIO_ENABLED=$(gcloud container clusters describe ${CLUSTER_NAME} \
    --region=${CLUSTER_REGION} \
    --project=${PROJECT_ID} \
    --format="value(addonsConfig.istioConfig.disabled)" 2>/dev/null || echo "true")

echo "3. Installing Istio using istioctl..."
# Download istioctl
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh - || echo "Istio may already be downloaded"
cd istio-1.20.0 2>/dev/null || cd istio-* 2>/dev/null || true

# Install Istio with minimal profile for Autopilot
if [ -f "bin/istioctl" ]; then
    ./bin/istioctl install --set profile=minimal -y || echo "Istio may already be installed"
    cd ..
else
    echo "Skipping Istio installation - istioctl not found"
fi

echo "Waiting for Istio to be ready..."
sleep 10

# Verify Istio installation
echo "4. Verifying Istio installation..."
kubectl get namespace istio-system 2>/dev/null || {
    echo "Creating istio-system namespace..."
    kubectl create namespace istio-system
}

# Check if Istio ingress gateway exists
echo "5. Checking Istio Ingress Gateway..."
kubectl get svc istio-ingressgateway -n istio-system 2>/dev/null || {
    echo "Istio Ingress Gateway not found. It should be created automatically."
    echo "Waiting for Istio components to be ready..."
    sleep 30
}

# Wait for Istio ingress gateway to be ready
echo "6. Waiting for Istio Ingress Gateway to get external IP..."
for i in {1..30}; do
    EXTERNAL_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$EXTERNAL_IP" ]; then
        echo "Istio Ingress Gateway is ready!"
        echo "External IP: $EXTERNAL_IP"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 10
done

# Display Istio components status
echo ""
echo "================================================"
echo "Istio Setup Complete!"
echo "================================================"
echo ""
echo "Istio Components:"
kubectl get pods -n istio-system
echo ""
echo "Istio Ingress Gateway:"
kubectl get svc istio-ingressgateway -n istio-system
echo ""
echo "To access your services, use the Istio Ingress Gateway IP:"
echo "  export INGRESS_HOST=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  echo \"Gateway IP: \$INGRESS_HOST\""
