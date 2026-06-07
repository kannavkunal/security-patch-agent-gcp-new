#!/bin/bash
set -e

echo "================================================"
echo "Installing Monitoring Stack"
echo "Prometheus + Grafana + Kiali"
echo "================================================"
echo ""

# Add Helm repositories
echo "1. Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add kiali https://kiali.org/helm-charts
helm repo update

# Create monitoring namespace
echo "2. Creating monitoring namespace..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install Prometheus + Grafana stack
echo "3. Installing Prometheus + Grafana (kube-prometheus-stack)..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin \
  --set grafana.service.type=LoadBalancer \
  --set prometheus.service.type=LoadBalancer \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --wait \
  --timeout 10m

echo "4. Installing Kiali (Istio Dashboard)..."
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml -n istio-system || echo "Kiali resources may already exist"

# Expose Kiali via LoadBalancer
kubectl patch svc kiali -n istio-system -p '{"spec": {"type": "LoadBalancer"}}' || echo "Kiali service already configured"

# Wait for services to get external IPs
echo "5. Waiting for external IPs to be assigned..."
sleep 30

# Get service URLs
GRAFANA_IP=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
PROMETHEUS_IP=$(kubectl get svc prometheus-kube-prometheus-prometheus -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
KIALI_IP=$(kubectl get svc kiali -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")

echo ""
echo "================================================"
echo "Monitoring Stack Installed!"
echo "================================================"
echo ""
echo "📊 GRAFANA (Metrics & Dashboards):"
if [ "$GRAFANA_IP" != "pending" ]; then
  echo "   URL: http://$GRAFANA_IP"
else
  echo "   URL: External IP pending... Run this to check:"
  echo "   kubectl get svc prometheus-grafana -n monitoring"
fi
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "📈 PROMETHEUS (Metrics Database):"
if [ "$PROMETHEUS_IP" != "pending" ]; then
  echo "   URL: http://$PROMETHEUS_IP:9090"
else
  echo "   URL: External IP pending... Run this to check:"
  echo "   kubectl get svc prometheus-kube-prometheus-prometheus -n monitoring"
fi
echo ""
echo "🕸️  KIALI (Istio Service Mesh Dashboard):"
if [ "$KIALI_IP" != "pending" ]; then
  echo "   URL: http://$KIALI_IP:20001"
else
  echo "   URL: External IP pending... Run this to check:"
  echo "   kubectl get svc kiali -n istio-system"
fi
echo ""
echo "================================================"
echo "Next: Import custom dashboards"
echo "Run: ./import-dashboards.sh"
echo "================================================"
