#!/bin/bash
set -e

PROJECT_ID="${GCP_PROJECT_ID}"
CLUSTER_NAME="${GKE_CLUSTER:-code-vulnerability-scanner}"
CLUSTER_REGION="${GCP_LOCATION:-us-central1}"

if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: GCP_PROJECT_ID environment variable is not set"
    exit 1
fi

echo "================================================"
echo "Setting up GCP Native Monitoring"
echo "Cloud Monitoring + Cloud Logging + Cloud Trace"
echo "================================================"
echo ""

# Enable required APIs
echo "1. Enabling GCP Monitoring APIs..."
gcloud services enable \
    monitoring.googleapis.com \
    logging.googleapis.com \
    cloudtrace.googleapis.com \
    clouderrorreporting.googleapis.com \
    cloudprofiler.googleapis.com \
    --project=$PROJECT_ID

echo "2. Enabling GKE monitoring features..."
# Enable Cloud Monitoring for GKE
gcloud container clusters update $CLUSTER_NAME \
    --region=$CLUSTER_REGION \
    --enable-cloud-logging \
    --enable-cloud-monitoring \
    --logging=SYSTEM,WORKLOAD \
    --monitoring=SYSTEM,WORKLOAD \
    --project=$PROJECT_ID || echo "Monitoring already enabled"

echo ""
echo "================================================"
echo "GCP Native Monitoring Configured!"
echo "================================================"
echo ""
echo "🔗 Access your monitoring dashboards:"
echo ""
echo "📊 Cloud Monitoring (Metrics & Dashboards):"
echo "   https://console.cloud.google.com/monitoring?project=$PROJECT_ID"
echo ""
echo "📝 Cloud Logging (Logs Explorer):"
echo "   https://console.cloud.google.com/logs/query?project=$PROJECT_ID"
echo ""
echo "🔍 Cloud Trace (Distributed Tracing):"
echo "   https://console.cloud.google.com/traces/list?project=$PROJECT_ID"
echo ""
echo "☸️  GKE Workloads Dashboard:"
echo "   https://console.cloud.google.com/kubernetes/workload/overview?project=$PROJECT_ID"
echo ""
echo "================================================"
echo "Next: Creating custom dashboards in Cloud Monitoring"
echo "================================================"
