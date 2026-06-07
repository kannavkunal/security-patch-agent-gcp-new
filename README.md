# Security Patch Agent for GCP

**AI-Powered Security Vulnerability Remediation System**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GCP](https://img.shields.io/badge/GCP-Deployed-4285F4?logo=google-cloud)](https://cloud.google.com)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python)](https://python.org)

> **Production-ready** security automation system that detects vulnerabilities and generates AI-powered patches. Deploy to any GCP project in 15 minutes.

---

## 🎯 Overview

Automated security patch agent that:
- **Detects** vulnerabilities using static analysis (Bandit)
- **Generates** context-aware patches using Gemini 2.5 Pro
- **Creates** pull requests with detailed explanations
- **Learns** from past scans to improve patch quality

**Key Innovation:** LLM-powered context memory that learns repository-specific patterns.

---

## 📋 Quick Links

| Document | Description |
|----------|-------------|
| [**Installation Guide**](INSTALLATION.md) | Complete setup instructions (15 min) |
| [**Switch Project Guide**](SWITCH_PROJECT_GUIDE.md) | Deploy to different GCP projects |
| [**PRD**](submission-files/PRD.md) | Product requirements & architecture |
| [**Design Notes**](submission-files/DESIGN_NOTES.md) | Technical decisions & limitations |

---

## 🚀 Deploy to Your GCP Project

**Change these 2 secrets, run 1 workflow, wait 15 minutes:**

### Step 1: Set GitHub Secrets

Go to your repo → **Settings** → **Secrets and variables** → **Actions**:

```
GCP_PROJECT_ID: your-gcp-project-id
GCP_SA_KEY: <service-account-json-key>
API_KEY_PRIMARY: <openssl rand -hex 32>
API_KEY_SECONDARY: <openssl rand -hex 32>
```

### Step 2: Run Deployment

1. Go to **Actions** → **"Full Deployment"**
2. Click **"Run workflow"**
3. Select deployment options
4. Wait ~15 minutes

**Done!** The system is running in your GCP project.

---

## 🏗️ Architecture

```
GitHub Webhooks → FastAPI API → Pub/Sub → Worker → Kubernetes Jobs
                                                    ↓
                                        8-Phase Security Pipeline
                                                    ↓
                                    BigQuery (Audit) + GCS (Evidence)
```

**8-Phase Pipeline:**
1. **Repository Analysis** - Clone & analyze codebase
2. **Vulnerability Detection** - Bandit static analysis
3. **Context Planning** - LLM memory for smart remediation
4. **Patch Generation** - Gemini-powered code fixes
5. **Verification** - Stub (future: automated testing)
6. **GitHub Integration** - Create PR with explanations
7. **Audit Logging** - BigQuery compliance logs
8. **Evidence Generation** - CVSS reports to GCS

---

## 💡 Features

### Two Operating Modes

**PATCH Mode (Proactive)**
- Scans entire repository
- Detects all vulnerabilities
- Creates comprehensive fix PR

**REVIEW Mode (Reactive)**
- Triggered by PR webhooks
- Scans only PR diff
- Comments on vulnerabilities in-line

### Production-Ready Security

- ✅ API key authentication
- ✅ GitHub webhook HMAC validation
- ✅ Repository whitelisting
- ✅ Secrets in GCP Secret Manager
- ✅ Workload Identity (no service account keys in pods)
- ✅ No hardcoded project IDs (fully portable)

### Monitoring & Observability

- 3 Cloud Monitoring dashboards
- 5 log-based metrics
- 3 alert policies
- Full audit trail in BigQuery

---

## 🔧 Technology Stack

- **Compute:** GKE (Kubernetes)
- **AI/ML:** Vertex AI (Gemini 2.5 Pro)
- **Messaging:** Cloud Pub/Sub
- **Storage:** Cloud Storage, BigQuery
- **Security:** Secret Manager, Workload Identity
- **Monitoring:** Cloud Monitoring, Logging
- **IaC:** Terraform
- **CI/CD:** GitHub Actions

---

## 📊 Example Usage

### Trigger a Scan

```bash
# Get API key
API_KEY=$(kubectl get secret security-patch-agent-api-keys \
  -n security-patch-agent \
  -o jsonpath='{.data.api-keys}' | base64 -d | cut -d',' -f1)

# Trigger PATCH mode scan
curl -X POST http://<LOADBALANCER_IP>/scan \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "repo_url": "https://github.com/youruser/vulnerable-app",
    "mode": "patch",
    "branch": "main"
  }'
```

### Check Results

```bash
# Query audit logs
bq query --use_legacy_sql=false \
  'SELECT * FROM `your-project.security_scans.scans` 
   ORDER BY timestamp DESC LIMIT 5'

# View evidence files
gsutil ls gs://security-patch-evidence-your-project/

# Check GitHub PR
# → PR created automatically with fix explanation
```

---

## 💰 Cost Estimate

**~$750/month** for moderate usage:
- GKE cluster (e2-medium): ~$50
- Vertex AI (Gemini API): ~$650 (usage-based)
- Storage + Networking: ~$50

**Optimization tips:**
- Use GKE Autopilot (~30% savings)
- Enable Pub/Sub batching
- Set budget alerts

---

## 🧹 Cleanup

**Delete all resources:**

```bash
# Option 1: GitHub Actions workflow
Actions → "Cleanup - Destroy All Resources" → Type "DESTROY"

# Option 2: Script
export GCP_PROJECT_ID="your-project-id"
./cleanup.sh
```

**Cost after cleanup:** $0/month

---

## 📝 Project Structure

```
.
├── app/                      # Python application code
│   ├── main.py              # FastAPI service
│   ├── worker.py            # Pub/Sub worker
│   ├── orchestrator.py      # Pipeline coordinator
│   ├── phases/              # 8-phase pipeline
│   └── clients/             # BigQuery, GitHub, GCS
├── deployment/
│   └── k8s-manifests/       # Kubernetes YAML
├── infrastructure/
│   └── terraform/           # GCP infrastructure
├── .github/workflows/       # CI/CD automation
├── submission-files/        # Assignment deliverables
│   ├── PRD.md
│   ├── DESIGN_NOTES.md
│   └── README.md
├── cleanup.sh               # Resource deletion script
└── SWITCH_PROJECT_GUIDE.md  # Multi-project deployment
```

---

## 🚧 Known Limitations

**Phase 5 (Verification) is a stub:**
- Currently returns static success
- Future: Automated patch testing before PR creation
- See [DESIGN_NOTES.md](submission-files/DESIGN_NOTES.md) for full context

**Repository Whitelisting:**
- Only pre-configured repos can be scanned
- Prevents abuse in production deployment

---

## 📞 Contact

- **Email:** kannavkunal@gmail.com
- **GitHub:** [@kannavkunal](https://github.com/kannavkunal)

---

## 📄 License

MIT License - see [LICENSE](LICENSE)

---

## 🙏 Acknowledgments

Built for **Tessera Labs** Senior Software Engineer take-home assignment (June 2025).

**Technologies:** Google Cloud Platform, Vertex AI (Gemini 2.5 Pro), Python (FastAPI), Kubernetes, Terraform, GitHub Actions

---

**Ready to deploy?** → [INSTALLATION.md](INSTALLATION.md)
