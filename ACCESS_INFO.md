# Security Patch Agent - Access Information

## Web UI

**URL:** http://34.67.157.196/

The UI now displays the repository dropdown with 4 configured repositories.

## API Keys

**Primary API Key:**
```
1442dfa85c5942bd2102a99b8edbfc67ff7d27f725d0f5ee1ba67ac551fc4cbe
```

**Secondary API Key:**
```
326b19e874928fbf0e3196f3691d78f855172908d88b3445cc8fa2e2caaef028
```

## Configured Repositories

The system is configured to scan these 4 repositories:

1. https://github.com/kannavkunal/vulnerable-python-api
2. https://github.com/kannavkunal/vulnerable-node-service
3. https://github.com/kannavkunal/vulnerable-go-microservice
4. https://github.com/kannavkunal/vulnerable-java-app

## API Endpoints

### Health Check
```bash
curl http://34.67.157.196/health
```

### List Repositories
```bash
curl http://34.67.157.196/repositories
```

### Trigger Scan (requires API key)
```bash
curl -X POST http://34.67.157.196/scan \
  -H "Content-Type: application/json" \
  -H "X-API-Key: 1442dfa85c5942bd2102a99b8edbfc67ff7d27f725d0f5ee1ba67ac551fc4cbe" \
  -d '{
    "repo_url": "https://github.com/kannavkunal/vulnerable-python-api",
    "mode": "patch",
    "branch": "main"
  }'
```

### List Scans (requires API key)
```bash
curl -H "X-API-Key: 1442dfa85c5942bd2102a99b8edbfc67ff7d27f725d0f5ee1ba67ac551fc4cbe" \
  http://34.67.157.196/scans?limit=10
```

## Webhook Configuration

**Webhook URL:** http://34.67.157.196/webhook/github

**Webhook Secret:**
```
47dca8eeae767c5f07f4967864feadcdcb34688f41022c2c8e7402662e474cd3
```

Configure webhooks on all 4 repositories using the instructions in [WEBHOOK_SETUP.md](./WEBHOOK_SETUP.md).

## Quick Start

1. **Open Web UI**: http://34.67.157.196/
2. **Enter API Key**: `1442dfa85c5942bd2102a99b8edbfc67ff7d27f725d0f5ee1ba67ac551fc4cbe`
3. **Select Repository**: Choose from the dropdown
4. **Scan Mode**: Select `PATCH` or `REVIEW`
5. **Click**: "Start Scan"

## Testing

Run comprehensive tests:
```bash
export GCP_PROJECT_ID=security-patch-agent-gcp
export API_IP=34.67.157.196
export API_KEY=1442dfa85c5942bd2102a99b8edbfc67ff7d27f725d0f5ee1ba67ac551fc4cbe

./test_e2e_complete.sh
```

## GCP Resources

- **Project ID**: security-patch-agent-gcp
- **GKE Cluster**: code-vulnerability-scanner
- **Region**: us-central1
- **Namespace**: security-patch-agent
- **BigQuery Dataset**: security_scans
- **GCS Bucket**: security-patch-evidence-security-patch-agent-gcp

## Monitoring

**Cloud Console:**
- Workloads: https://console.cloud.google.com/kubernetes/workload?project=security-patch-agent-gcp
- Monitoring: https://console.cloud.google.com/monitoring?project=security-patch-agent-gcp
- Logging: https://console.cloud.google.com/logs/query?project=security-patch-agent-gcp
- BigQuery: https://console.cloud.google.com/bigquery?project=security-patch-agent-gcp&d=security_scans

**kubectl Commands:**
```bash
# View pods
kubectl get pods -n security-patch-agent --insecure-skip-tls-verify

# View logs (API)
kubectl logs -n security-patch-agent -l app=security-patch-agent -c api -f --insecure-skip-tls-verify

# View logs (Worker)
kubectl logs -n security-patch-agent -l app=security-patch-agent -c worker -f --insecure-skip-tls-verify

# View jobs
kubectl get jobs -n security-patch-agent --insecure-skip-tls-verify

# View services
kubectl get svc -n security-patch-agent --insecure-skip-tls-verify
```
