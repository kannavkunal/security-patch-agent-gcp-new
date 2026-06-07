#!/bin/bash

PROJECT_ID="compact-orb-498606-f9"
REGION="us-central1"

echo "================================================"
echo "Deployment Status Check"
echo "================================================"
echo ""

# Check Cloud Build status
echo "📦 Cloud Build Status:"
gcloud builds list --limit=1 --project=$PROJECT_ID --format="table(id,status,createTime,duration)"
echo ""

# Check if we can access the cluster
echo "🔍 Checking GKE Cluster..."
gcloud container clusters describe code-vulnerability-scanner \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="value(status,currentNodeCount)" 2>/dev/null || echo "Checking..."
echo ""

echo "📊 View detailed build logs:"
echo "https://console.cloud.google.com/cloud-build/builds?project=$PROJECT_ID"
echo ""

echo "☸️  View GKE workloads:"
echo "https://console.cloud.google.com/kubernetes/workload?project=$PROJECT_ID"
echo ""
