# Architecture Deep Dive

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER INTERACTION                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   Web UI / API   │
                    │  (FastAPI - API) │
                    │  Port 8080       │
                    └──────────────────┘
                              │
                              │ 1. POST /scan
                              ▼
                    ┌──────────────────┐
                    │  Publish Event   │
                    │  to Pub/Sub      │
                    └──────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GCP PUB/SUB SERVICE                           │
│                                                                  │
│  Topic: security-scan-events                                    │
│  Subscription: scan-events-subscription                         │
│  DLQ: security-scan-events-dlq                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 2. Pull messages
                              ▼
                    ┌──────────────────┐
                    │   Worker         │
                    │ (Container #2)   │
                    │ app/worker.py    │
                    └──────────────────┘
                              │
                              │ 3. Spawn Job
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    KUBERNETES JOB                                │
│                                                                  │
│  8-Phase Security Scan:                                         │
│  1. Repository Analysis                                         │
│  2. Vulnerability Detection (Semgrep/Bandit)                   │
│  3. Planning with Context (LLM + Past Scans)                   │
│  4. Patch Generation (Gemini 2.5 Pro)                          │
│  5. Verification (Stub - future)                               │
│  6. GitHub Integration (Create PR)                             │
│  7. Audit Logging (BigQuery)                                   │
│  8. Evidence Generation (Security Reports)                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Two-Container Pod Architecture

The main deployment runs **2 containers simultaneously** in a single pod:

### Container 1: API (FastAPI)
- **Image:** `us-central1-docker.pkg.dev/PROJECT_ID/security-patch-agent/api:latest`
- **Command:** `uvicorn app.main:app --host 0.0.0.0 --port 8080`
- **Port:** 8080
- **Role:** 
  - Serves Web UI
  - Handles REST API (`/scan`, `/repositories`, `/scans`)
  - **Publishes** scan requests to Pub/Sub
  - Returns scan_id to user

### Container 2: Worker (Pub/Sub Listener)
- **Image:** Same as API (same image, different entrypoint)
- **Command:** `python -m app.worker`
- **Role:**
  - **Listens** to Pub/Sub subscription continuously
  - Validates scan requests (repo whitelist, branch name)
  - Creates Kubernetes Jobs for scans
  - Handles webhook events from GitHub

## Event Flow

### Manual Scan (PATCH mode):
```
1. User clicks "Start Scan" in Web UI
2. API receives POST /scan
3. API publishes message to Pub/Sub topic
4. Worker receives message from subscription
5. Worker validates request
6. Worker creates K8s Job
7. Job pod starts, runs 8 phases
8. Job creates PR with fixes
9. Job logs results to BigQuery
10. Job completes, pod auto-deletes (TTL: 5min)
```

### Webhook Scan (REVIEW mode):
```
1. Developer creates PR on GitHub
2. GitHub sends webhook POST /webhook/github
3. API validates HMAC signature
4. API publishes "review" message to Pub/Sub
5. Worker creates K8s Job in REVIEW mode
6. Job scans PR branch only
7. Job posts security comment on PR
8. Job completes
```

## Data Flow

### Phase 3: LLM Context Memory
```
┌─────────────────────┐
│  Current Scan       │
│  (9 vulnerabilities)│
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│  BigQuery Query     │
│  Past scans for     │
│  this repository    │
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│  Context Builder    │
│  - Previous vulns   │
│  - Previous fixes   │
│  - Patterns learned │
└─────────────────────┘
          │
          ▼
┌─────────────────────┐
│  Gemini 2.5 Pro     │
│  Generates patches  │
│  with context       │
└─────────────────────┘
```

## Security Layers

### 1. Authentication & Authorization
- **API Keys:** HMAC-SHA256 validated on every request
- **GitHub Webhooks:** HMAC-SHA256 signature verification
- **Workload Identity:** Pods use GCP service accounts (no key files)
- **Secret Manager:** All credentials centralized

### 2. Network Security
- **LoadBalancer:** Public IP for API (34.67.157.196)
- **Firewall:** GKE auto-configured
- **mTLS:** Not implemented (future: Istio service mesh)

### 3. Job Isolation
- **Separate Pod per Scan:** No shared state
- **Resource Limits:** CPU/memory quotas
- **TTL Cleanup:** Auto-delete after 5 minutes
- **Namespace Isolation:** All resources in `security-patch-agent` namespace

### 4. Repository Access Control
- **Whitelist:** Only 4 test repos allowed
- **GitHub Token:** Fine-grained PAT (repo scope only)
- **No Auto-Merge:** All PRs require human approval

## Scalability Design

### Horizontal Scaling
```
┌─────────────────────────────────────────────────────────────┐
│  Load Balancer (Cloud Load Balancer)                        │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        ┌──────────┐    ┌──────────┐    ┌──────────┐
        │  Pod 1   │    │  Pod 2   │    │  Pod 3   │
        │ API+Work │    │ API+Work │    │ API+Work │
        └──────────┘    └──────────┘    └──────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │    Pub/Sub       │
                    │  (Distributed)   │
                    └──────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        ┌──────────┐    ┌──────────┐    ┌──────────┐
        │ Job Pod  │    │ Job Pod  │    │ Job Pod  │
        │ Scan 1   │    │ Scan 2   │    │ Scan 3   │
        └──────────┘    └──────────┘    └──────────┘
```

**Current:** 1 replica (demo)  
**Production:** 3+ replicas behind LB  
**Max throughput:** ~100 concurrent scans (K8s autoscaler)

### Cost Optimization
- **GKE Autopilot:** Pay per pod, not node
- **Pub/Sub:** $0.40 per million messages
- **BigQuery:** On-demand pricing ($5/TB scanned)
- **Gemini API:** $1-2 per scan
- **Total:** ~$750/month for 200 scans

## Monitoring & Observability

### Metrics (Cloud Monitoring)
```
- scan_duration_seconds (histogram)
- scan_total (counter by status)
- vulnerability_count (gauge)
- patch_success_rate (gauge)
- pubsub_message_age_seconds (histogram)
```

### Logs (Cloud Logging)
```
- Structured JSON logs from all pods
- Log severity: INFO, WARNING, ERROR
- Query: resource.type="k8s_pod" AND resource.labels.namespace_name="security-patch-agent"
```

### Dashboards (Cloud Console)
1. **Scan Overview:** Success rate, duration, vulnerabilities
2. **Infrastructure:** Pod health, resource usage
3. **Pub/Sub:** Message latency, delivery failures

## Failure Handling

### Pub/Sub Reliability
- **Dead Letter Queue:** Failed messages after 5 retries
- **Ack Deadline:** 5 minutes (enough for scan completion)
- **Exactly-Once:** Prevents duplicate scans

### Job Failures
- **Retry:** Manual retry via API (no auto-retry to avoid loops)
- **Logging:** All errors written to BigQuery
- **Cleanup:** Failed jobs auto-delete after 5 min

### LLM Failures
- **Template Fallback:** If Gemini fails, use basic patch template
- **Partial Success:** Generate patches for successful files only
- **Error Logging:** LLM errors logged for debugging

## Deployment Pipeline

### CI/CD (GitHub Actions)
```
1. Push to main branch
2. Build Docker image
3. Push to Artifact Registry
4. Update K8s manifests (sed PROJECT_ID)
5. Apply ConfigMap (VULNERABLE_REPOS)
6. Deploy to GKE
7. Restart pods (rolling update)
8. Health check (wait for ready)
```

**Duration:** ~10-15 minutes  
**Zero Downtime:** Rolling updates

## Infrastructure as Code

### Terraform Resources
```
- GKE Cluster (Autopilot)
- Pub/Sub Topic + Subscription + DLQ
- BigQuery Dataset + Tables
- Secret Manager Secrets
- IAM Service Accounts + Bindings
- GCS Bucket (Evidence storage)
```

**Command:** `terraform apply`  
**Destroy:** `terraform destroy`

### Kubernetes Manifests
```
- Namespace
- ServiceAccount (Workload Identity)
- ConfigMap (VULNERABLE_REPOS)
- Secret (API keys)
- Deployment (API + Worker)
- Service (LoadBalancer)
- Job Template (Scanner)
```

## Future Architecture Improvements

### 1. Multi-Region Deployment
```
┌─────────────────────────────────────────────────────────────┐
│  Global Load Balancer (Cloud CDN)                           │
└─────────────────────────────────────────────────────────────┘
              │                                  │
              ▼                                  ▼
    ┌──────────────────┐            ┌──────────────────┐
    │  us-central1     │            │  europe-west1    │
    │  GKE Cluster     │            │  GKE Cluster     │
    └──────────────────┘            └──────────────────┘
              │                                  │
              └──────────────┬───────────────────┘
                             ▼
                  ┌──────────────────────┐
                  │  Spanner (Global DB) │
                  └──────────────────────┘
```

### 2. Microservices Split
- **Scanner Service:** Runs Semgrep/Bandit only
- **LLM Service:** Generates patches only
- **GitHub Service:** Manages PRs only

### 3. Caching Layer
- **Redis:** Cache vulnerability scan results (24h TTL)
- **Benefit:** Faster rescans of same commit

---

**Last Updated:** June 7, 2026
