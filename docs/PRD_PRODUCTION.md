# Product Requirements Document
## Security Patch Agent: Production-Grade Autonomous Vulnerability Remediation

**Version:** 1.0  
**Author:** Kunal Kannav, Principal Engineer  
**Date:** June 2026  
**Status:** Production Deployment (GKE)

---

## Executive Summary

Security Patch Agent is an **event-driven, AI-powered remediation platform** that closes the loop between vulnerability detection and code fixes. Built on production-grade Kubernetes infrastructure, the system demonstrates how modern platform engineering principles (event-driven architecture, LLM integration, comprehensive observability) can solve the security debt crisis.

**Current State:**
- ✅ Deployed on GKE Autopilot (security-patch-agent-gcp-new)
- ✅ Processing scans end-to-end (detect → patch → PR → evidence)
- ✅ Full observability stack (BigQuery analytics, GCS evidence, monitoring)
- ✅ Event-driven architecture (Pub/Sub → Worker → K8s Jobs)

**This PRD focuses on production considerations, bottlenecks, and evolution to enterprise scale.**

---

## 1. Problem Statement

### The Security Remediation Gap

**Industry Reality:**
- Median time-to-remediation: 60+ days (Veracode 2025)
- Security teams manually triage 1000s of alerts
- Developers context-switch to fix week-old vulnerabilities
- Compliance requires manual evidence collection (40+ hours/audit)

**Technical Root Causes:**
1. **Detection tools don't remediate** - SAST tools (Snyk, Semgrep) only report issues
2. **No differential analysis** - PR scans show 147 vulns on 3-line changes (alert fatigue)
3. **Manual evidence assembly** - Screenshots across Jira/GitHub/Slack for auditors
4. **Stateless scanning** - Tools don't learn from past fixes (repeated mistakes)

### Why This Matters for Platform Engineering

As infrastructure teams scale to support 500+ developers:
- **Developer velocity** blocked by security gates
- **CI/CD pipelines** fail on vulnerabilities (no auto-fix)
- **Compliance overhead** grows linearly with team size
- **Security debt** accumulates faster than manual remediation

---

## 2. Solution Architecture

### 2.1 High-Level Design

```
External Actors          |  Edge Layer              |  Compute Layer (GKE)           |  Data Layer
-------------------------|--------------------------|--------------------------------|------------------
GitHub Repositories  →   |  LoadBalancer            |  API Pod (FastAPI)             |  BigQuery
Developers (Web UI)  →   |  (Future: Istio Ingress) |  Worker Pod (Pub/Sub consumer) |  Cloud Storage
Security Teams       →   |  mTLS, Auth              |  Scanner Jobs (ephemeral)      |  Secret Manager
                         |                          |  (Future: Redis cache)         |  
```

**Key Architectural Decisions:**

1. **Event-Driven vs. Synchronous**
   - **Chosen:** Pub/Sub message queue between API and jobs
   - **Why:** Decouples API from scan execution, provides durability, enables backpressure
   - **Trade-off:** Added latency (~5s) vs. reliability

2. **Ephemeral Jobs vs. Long-Running Workers**
   - **Chosen:** K8s Jobs (spawn per scan, auto-cleanup)
   - **Why:** Isolation (no state leakage), automatic cleanup, resource efficiency
   - **Trade-off:** Pod startup overhead (~15s) vs. security/isolation

3. **LLM Choice: Gemini vs. GPT-4**
   - **Chosen:** Google Gemini 2.5 Pro
   - **Why:** Native GCP integration, lower latency, better code generation benchmarks
   - **Cost:** ~$1.50/scan (acceptable for PoC, needs optimization for scale)

### 2.2 Component Breakdown

#### API Layer (FastAPI + Uvicorn)
**Responsibilities:**
- Authenticate requests (API key + future OAuth/OIDC)
- Validate input (Pydantic models, repository whitelist)
- Publish to Pub/Sub
- Serve Web UI (React-style SPA)
- Query BigQuery for scan history

**Current Limitations:**
- No rate limiting
- API keys in Secret Manager (no rotation policy)
- Single replica (no HA)

#### Worker Layer (Pub/Sub Subscriber)
**Responsibilities:**
- Listen for scan events
- Spawn Kubernetes Jobs with scan context
- Handle retries (dead letter queue for failures)

**Current Configuration:**
- Exactly-once delivery enabled
- 5 retry attempts before DLQ
- 300s ack deadline

#### Scanner Jobs (8-Phase Orchestrator)
**Phases:**
1. **Analyze** - Detect languages, dependency files
2. **Detect** - Run Semgrep + custom rules
3. **Plan** - Query BigQuery for historical context
4. **Patch** - Generate fixes with Gemini LLM
5. **Verify** - (Future: run tests, static analysis)
6. **GitHub** - Create branch, update files, create PR
7. **Log** - Insert to BigQuery (scans, vulnerabilities, patches)
8. **Evidence** - Generate markdown reports, upload to GCS

**Resource Limits:**
- CPU: 500m request, 2 core limit
- Memory: 1Gi request, 4Gi limit
- Timeout: 30 minutes

---

## 3. Production Considerations

### 3.1 Scalability Bottlenecks

#### Identified Constraints:

1. **GKE Cluster Auto-Scaling**
   - **Current:** 2-node Autopilot cluster
   - **Bottleneck:** Hit GCP quota limits when >2 scans run concurrently
   - **Impact:** Second scan queued for 4+ minutes waiting for node spin-up
   - **Solution:** Request quota increase OR implement scan queuing with max concurrency

2. **LLM API Rate Limits**
   - **Current:** Gemini API has quota (requests/minute)
   - **Bottleneck:** Concurrent scans hit rate limits
   - **Impact:** Phase 4 (patching) fails with 429 errors
   - **Solution:** Implement exponential backoff + request queuing

3. **BigQuery Insert Latency**
   - **Current:** Synchronous inserts in Phase 7
   - **Bottleneck:** Each insert adds ~500ms to scan time
   - **Impact:** Total scan time increased by 2-3 seconds
   - **Solution:** Batch inserts OR async background task

4. **GitHub API Rate Limits**
   - **Current:** 5000 requests/hour (authenticated)
   - **Bottleneck:** Large repos with many files hit limit
   - **Impact:** PR creation fails
   - **Solution:** Conditional requests (ETags), minimize API calls

### 3.2 Reliability & Fault Tolerance

#### Current Gaps:

**Single Points of Failure:**
- API pod (1 replica) - service downtime if pod crashes
- Worker pod (1 replica) - scans not processed if worker fails
- No circuit breaker for external services (GitHub, Gemini)

**Recommended Improvements:**
```yaml
# High Availability Configuration
replicas:
  api: 3      # Multi-zone placement
  worker: 2   # Active-active consumers

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

**Circuit Breaker Pattern:**
- Implement retries with exponential backoff for Gemini API
- Fallback to template-based fixes if LLM unavailable
- Dead letter queue already configured (good!)

### 3.3 Security Hardening

#### Current Security Controls:

✅ **Implemented:**
- API key authentication
- GitHub webhook HMAC signature validation
- Secret Manager for credentials (GitHub token, webhook secret)
- Workload Identity (no service account keys)
- Git credential prompting disabled (prevents token leakage)
- Repository whitelist (prevents arbitrary repo scanning)
- Non-root container user

#### Production Security Roadmap:

**Phase 1: Network Security (Istio Service Mesh)**
```yaml
# Mutual TLS between services
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: security-patch-agent
spec:
  mtls:
    mode: STRICT  # Enforce mTLS for all traffic

---
# Authorization Policies
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: api-policy
spec:
  selector:
    matchLabels:
      app: security-patch-agent
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/security-patch-agent/sa/worker-sa"]
    to:
    - operation:
        methods: ["POST"]
        paths: ["/internal/*"]
```

**Phase 2: Istio Ingress Gateway**
- Replace LoadBalancer with Istio Gateway
- TLS termination at edge
- Rate limiting at ingress layer
- Web Application Firewall (WAF) integration

**Phase 3: Network Policies**
```yaml
# Restrict egress to only required services
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-egress
spec:
  podSelector:
    matchLabels:
      app: security-patch-agent
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: pubsub  # Allow Pub/Sub
    - podSelector:
        matchLabels:
          app: bigquery  # Allow BigQuery
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # HTTPS only
```

**Phase 4: Secrets Rotation**
- GitHub token auto-rotation (30-day TTL)
- API key rotation policy
- Audit logging for secret access

### 3.4 Observability & Monitoring

#### Current Instrumentation:

✅ **Metrics (Prometheus):**
- HTTP request latency (API)
- Scan duration by phase
- Error rates
- Pod resource usage

✅ **Logs (Cloud Logging):**
- Structured JSON logs
- Trace IDs for request correlation
- Phase-level logging

✅ **Traces (Future: OpenTelemetry)**
- End-to-end request tracing
- LLM API call tracing
- GitHub API call tracing

#### Recommended Dashboards:

**SLI/SLO Dashboard:**
```
Service Level Indicators:
- API availability (target: 99.9%)
- Scan success rate (target: 95%)
- P99 scan latency (target: <5 minutes)

Alerts:
- Error rate >1% for 5 minutes
- Scan queue depth >10 for 10 minutes
- API latency P99 >500ms for 5 minutes
```

**Cost Dashboard:**
```
Cost Attribution:
- GKE node hours
- Gemini API calls ($/scan)
- BigQuery storage + query costs
- GCS egress (evidence downloads)
```

---

## 4. Performance Optimization

### 4.1 Caching Strategy (Future: Redis)

**Problem:**
- Re-scanning same repository wastes LLM credits
- Historical scan queries hit BigQuery (slow + costly)

**Solution: Multi-Layer Cache**

```
Layer 1: In-Memory Cache (API pod)
├── Repository metadata (languages, file tree)
├── Recent scan results (last 24h)
└── TTL: 1 hour

Layer 2: Redis (Shared)
├── Scan results (keyed by repo + commit SHA)
├── LLM responses (keyed by vulnerability signature)
├── BigQuery query results
└── TTL: 7 days

Layer 3: BigQuery (Cold Storage)
└── All historical scans
```

**Expected Impact:**
- 70% reduction in BigQuery queries
- 40% reduction in Gemini API calls (cached fixes)
- P99 latency improvement: 5min → 2min

### 4.2 Evidence Generation Optimization

**Current Bottleneck:**
- Phase 8 generates 20+ markdown files using LLM
- Each LLM call adds ~3-5 seconds
- Total: 60-100 seconds per scan

**Optimization:**
- Parallelize LLM calls (async batch requests)
- Use template-based generation for simple findings
- Only use LLM for complex attack scenarios

**Expected Impact:**
- Evidence generation time: 100s → 30s

---

## 5. Multi-Cloud Strategy

### 5.1 Current State: GCP-Native

**Dependencies:**
- GKE (Kubernetes)
- Pub/Sub (messaging)
- BigQuery (analytics)
- Cloud Storage (evidence)
- Secret Manager (credentials)
- Vertex AI (Gemini LLM)

### 5.2 Multi-Cloud Abstraction Layer

**Phase 1: Abstract Messaging**
```python
# Abstract Pub/Sub interface
class MessageQueue(ABC):
    @abstractmethod
    def publish(self, topic: str, message: dict): pass
    
    @abstractmethod
    def subscribe(self, subscription: str, callback: Callable): pass

# Implementations:
class GCPPubSub(MessageQueue): ...  # Current
class AWSSQSSNSQueue(MessageQueue): ...  # Future
class AzureServiceBusQueue(MessageQueue): ...  # Future
```

**Phase 2: Abstract Storage**
```python
class ObjectStorage(ABC):
    @abstractmethod
    def upload(self, path: str, data: bytes): pass
    
    @abstractmethod
    def download(self, path: str) -> bytes: pass

# Implementations:
class GCSStorage(ObjectStorage): ...  # Current
class S3Storage(ObjectStorage): ...  # Future
class AzureBlobStorage(ObjectStorage): ...  # Future
```

**Phase 3: Abstract Analytics**
- BigQuery → AWS Athena / Azure Synapse
- Use common query dialect (SQL)
- Abstract schema definitions

### 5.3 Hybrid Deployment Model

```
Primary Region (GCP us-central1):
├── GKE cluster (API, Worker)
├── Pub/Sub, BigQuery, GCS
└── Gemini AI (Vertex AI)

Failover Region (AWS us-east-1):
├── EKS cluster (standby)
├── SQS/SNS, Athena, S3
└── Bedrock (Claude/GPT-4)

Multi-Cloud Load Balancer:
└── Route traffic based on availability
```

---

## 6. Future Enhancements

### 6.1 Phase 5: Automated Verification

**Problem:** Currently, AI-generated patches are not validated

**Solution:**
```
Phase 5: Verify
├── Run existing unit tests
├── Run integration tests (if present)
├── Static analysis (linting, type checking)
├── Diff review (ensure only intended changes)
└── Flag high-risk changes for manual review
```

**Acceptance Criteria:**
- If tests pass → Auto-merge PR (with approval workflow)
- If tests fail → Comment on PR with failure details
- If no tests → Create PR for manual review (current behavior)

### 6.2 Multi-Scanner Strategy

**Current:** Semgrep only

**Future:** Defense-in-Depth
```
Scanner Pipeline:
├── Semgrep (SAST for code)
├── Trivy (container image scanning)
├── Checkov (IaC scanning - Terraform, Helm)
├── Safety (Python dependency vulnerabilities)
├── npm audit (Node.js dependencies)
└── Custom rules (org-specific patterns)
```

**Deduplication Logic:**
- Same vulnerability detected by multiple scanners
- Merge findings by CVE ID / CWE ID
- Show confidence score (e.g., 3/6 scanners agree)

### 6.3 GitOps Integration

**Vision:** Security Patch Agent as a GitOps controller

```yaml
apiVersion: security.tessera.io/v1alpha1
kind: ScanPolicy
metadata:
  name: critical-repos
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  repositories:
    - https://github.com/org/critical-service-1
    - https://github.com/org/critical-service-2
  autoMerge:
    enabled: true
    conditions:
      - testsPass: true
      - maxSeverity: MEDIUM  # Auto-merge low/medium, manual for high/critical
      - approvedBy: [security-team, platform-team]
```

### 6.4 IDE Integration

**Developer Experience:**
- VSCode extension
- Real-time vulnerability detection (as you type)
- Inline fix suggestions (powered by LLM)
- One-click apply patches

### 6.5 Compliance Automation

**Auto-Generate Audit Reports:**
```
Quarterly Security Report:
├── Executive Summary
│   ├── Total vulnerabilities remediated
│   ├── Mean time to remediation
│   └── Compliance status (% of repos scanned)
├── Detailed Findings (by severity)
├── Evidence Package (GCS links)
└── Signed by Security Team
```

---

## 7. Cost Optimization

### 7.1 Current Spend Analysis

**Monthly Costs (Estimated):**
```
GKE Autopilot: $450
├── 2 nodes (e2-standard-4)
├── Persistent volumes (10GB)
└── Load Balancer

Gemini API: $150
├── 100 scans/month
├── ~$1.50/scan (avg 50 LLM calls)

BigQuery: $20
├── Storage: 10GB ($0.02/GB)
├── Queries: 500GB processed/month

Cloud Storage: $5
├── Evidence files: 50GB

Secret Manager: $1
├── 2 secrets, 200 accesses/month

Total: ~$626/month
```

### 7.2 Optimization Strategies

**Reduce GKE Costs:**
- Use Spot VMs for scanner jobs (70% savings)
- Auto-scale to zero during off-hours (weekends)
- Rightsize pod resource requests

**Reduce LLM Costs:**
- Cache LLM responses (Redis)
- Use cheaper model for simple fixes (Gemini Flash)
- Batch LLM requests

**Reduce BigQuery Costs:**
- Partition tables by date
- Cluster by scan_id
- Cache frequent queries

**Expected Savings: 40-50%** → **~$350/month**

---

## 8. Success Metrics

### 8.1 Product Metrics

**Efficiency:**
- Time-to-remediation: 60 days → 3 minutes (99.8% reduction)
- False positive rate: 98% → 2% (differential analysis)
- Audit prep time: 40 hours → 2 hours (95% reduction)

**Adoption:**
- Repositories scanned: 0 → 500 (target)
- PRs created: 0 → 200/month (target)
- PR merge rate: 0% → 85% (target)

**Reliability:**
- Scan success rate: 95% (target)
- API uptime: 99.9% (target)
- P99 scan latency: <5 minutes (target)

### 8.2 Business Impact

**Developer Productivity:**
- 80% reduction in context-switching (no manual fixes)
- 40% faster merge-to-production (automated security gates)

**Security Posture:**
- 100% coverage of security gates (every PR scanned)
- Mean time to detect (MTTd): <5 minutes (REVIEW mode)
- Mean time to remediate (MTTr): <1 day (vs. 60 days)

**Compliance:**
- SOC 2 audit time: 40 hours → 5 hours
- Evidence ready in real-time (no manual assembly)

---

## 9. Risks & Mitigations

### 9.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| LLM-generated fix is incorrect | High | Medium | Phase 5 verification, manual review required |
| GitHub API rate limit | Medium | High | Implement caching, conditional requests |
| GKE quota limits | Medium | Medium | Request quota increase, implement queue |
| Pub/Sub message loss | Low | High | Exactly-once delivery enabled, DLQ configured |
| Secret leakage | Low | Critical | Workload Identity, no keys in code, audit logs |

### 9.2 Operational Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Cost overrun (LLM API) | Medium | Medium | Set budget alerts, cache aggressively |
| Alert fatigue (too many PRs) | Medium | Low | Smart batching, weekly digest mode |
| Developers ignore PRs | Medium | Medium | Gamification, leaderboard, metrics |

---

## 10. Appendix

### 10.1 Architecture Evolution

**v1.0 (Current):**
- Single GCP region
- Synchronous processing
- Manual evidence review

**v1.5 (6 months):**
- Istio service mesh
- Redis caching layer
- Multi-scanner support
- Phase 5 verification

**v2.0 (12 months):**
- Multi-cloud (AWS failover)
- GitOps controller
- Auto-merge with approvals
- IDE integration

### 10.2 References

**Standards:**
- OWASP Top 10 (vulnerability categories)
- CWE (Common Weakness Enumeration)
- CVSS v3.1 (severity scoring)

**Tools:**
- Semgrep: https://semgrep.dev
- Gemini: https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini
- Istio: https://istio.io/latest/docs/

---

**Document Owner:** Kunal Kannav  
**Reviewers:** [TBD]  
**Last Updated:** June 2026  
**Next Review:** July 2026
