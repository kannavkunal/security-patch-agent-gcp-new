#!/bin/bash
set -e

echo "================================================"
echo "Importing Custom Grafana Dashboards"
echo "================================================"
echo ""

# Wait for Grafana to be ready
echo "1. Waiting for Grafana to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s

# Get Grafana service IP
GRAFANA_IP=$(kubectl get svc prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$GRAFANA_IP" ]; then
    echo "Error: Grafana external IP not yet assigned"
    echo "Run this command to check status:"
    echo "  kubectl get svc prometheus-grafana -n monitoring"
    exit 1
fi

echo "2. Grafana URL: http://$GRAFANA_IP"
echo ""

# Port forward to Grafana (alternative to LoadBalancer)
echo "3. Setting up port-forward to Grafana..."
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 > /dev/null 2>&1 &
PF_PID=$!
sleep 5

# Import dashboard using Grafana API
echo "4. Importing Security Patch Agent dashboard..."
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @dashboards/security-patch-agent-dashboard.json \
  2>/dev/null && echo "✅ Dashboard imported successfully!" || echo "⚠️  Dashboard import failed (may already exist)"

# Kill port-forward
kill $PF_PID 2>/dev/null || true

echo ""
echo "================================================"
echo "Dashboard Import Complete!"
echo "================================================"
echo ""
echo "Access Grafana at: http://$GRAFANA_IP"
echo "Username: admin"
echo "Password: admin"
echo ""
echo "Pre-installed dashboards:"
echo "  • Security Patch Agent - API Metrics (Custom)"
echo "  • Kubernetes / Compute Resources (Default)"
echo "  • Istio Service Dashboard (Default)"
echo "  • Istio Workload Dashboard (Default)"
echo ""
