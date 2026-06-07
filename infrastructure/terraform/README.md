# Terraform Infrastructure

This directory contains Terraform configurations for provisioning and managing the GCP infrastructure for the Security Patch Agent.

## What Gets Created

### GCP Resources

When you run `terraform apply` with `components = "all"`, the following resources are created:

#### 1. **GKE Autopilot Cluster**
- **Name**: `code-vulnerability-scanner`
- **Type**: Autopilot (fully managed)
- **Region**: us-central1
- **Features**:
  - Workload Identity enabled
  - Managed Prometheus monitoring
  - System and workload logging
  - Auto-scaling and auto-upgrading
  - Release channel: REGULAR

#### 2. **VPC Network**
- **Network**: `code-vulnerability-scanner-vpc`
- **Subnet**: `code-vulnerability-scanner-subnet`
  - Primary range: 10.0.0.0/24 (nodes)
  - Secondary range (pods): 10.1.0.0/16
  - Secondary range (services): 10.2.0.0/16
- **Private Google Access**: Enabled

#### 3. **Artifact Registry**
- **Repository**: `security-patch-agent`
- **Format**: Docker
- **Location**: us-central1
- **Cleanup Policy**: Keep last 10 tagged images, delete images older than 30 days

#### 4. **Service Accounts**
- **Name**: `security-patch-agent@PROJECT_ID.iam.gserviceaccount.com`
- **IAM Roles**:
  - `roles/aiplatform.user` (Vertex AI access)
  - `roles/logging.logWriter` (Cloud Logging)
  - `roles/monitoring.metricWriter` (Cloud Monitoring)
  - `roles/cloudtrace.agent` (Cloud Trace)
- **Workload Identity**: Bound to Kubernetes service account

#### 5. **Monitoring Alerts**
- **High Error Rate Alert**: Triggers when error rate >5%
- **Pod Restart Alert**: Notifies on pod restarts
- **Notification Channel**: Email alerts

#### 6. **APIs Enabled**
- Kubernetes Engine API
- Compute Engine API
- Artifact Registry API
- Cloud Build API
- Cloud Monitoring API
- Cloud Logging API
- Cloud Trace API
- Vertex AI API
- Service Networking API

## Variables

### Required

None - all variables have defaults

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP Project ID | `compact-orb-498606-f9` |
| `region` | GCP region | `us-central1` |
| `cluster_name` | GKE cluster name | `code-vulnerability-scanner` |
| `namespace` | Kubernetes namespace | `security-patch-agent` |
| `components` | What to deploy | `all` |
| `alert_email` | Email for alerts | `kunal@example.com` |
| `whitelisted_ips` | Allowed IPs | `["199.167.52.5/32"]` |

### Component Options

The `components` variable allows selective deployment:

- **`all`**: Deploy everything (default)
- **`gke-only`**: GKE cluster, VPC, service accounts only
- **`artifact-registry-only`**: Just the Docker repository
- **`monitoring-only`**: Alert policies and notification channels only

## Usage

### Prerequisites

1. **GCS Bucket for Terraform State**

   Create the bucket (one-time setup):
   ```bash
   gsutil mb -p compact-orb-498606-f9 -l us-central1 \
     gs://compact-orb-498606-f9-terraform-state
   
   gsutil versioning set on \
     gs://compact-orb-498606-f9-terraform-state
   ```

2. **Authenticate to GCP**
   ```bash
   gcloud auth application-default login
   # OR
   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
   ```

### Local Deployment

```bash
cd infrastructure/terraform

# Initialize Terraform
terraform init

# Preview changes
terraform plan \
  -var="components=all" \
  -out=tfplan

# Apply changes
terraform apply tfplan

# View outputs
terraform output
```

### Via GitHub Actions

See [Deploy Infrastructure workflow](../../.github/workflows/deploy-infrastructure.yml)

1. Go to **Actions** → **Deploy Infrastructure**
2. Click **Run workflow**
3. Select:
   - Action: `plan` or `apply`
   - Components: `all`, `gke-only`, etc.

### Component-Specific Deployments

#### Deploy only GKE cluster
```bash
terraform apply -var="components=gke-only"
```

#### Deploy only Artifact Registry
```bash
terraform apply -var="components=artifact-registry-only"
```

#### Update monitoring only
```bash
terraform apply -var="components=monitoring-only"
```

## Outputs

After `terraform apply`, these outputs are available:

| Output | Description |
|--------|-------------|
| `cluster_name` | GKE cluster name |
| `cluster_endpoint` | GKE API server endpoint |
| `cluster_ca_certificate` | Cluster CA cert (base64) |
| `service_account_email` | Workload Identity service account |
| `artifact_registry_url` | Docker repository URL |
| `vpc_network_name` | VPC network name |
| `subnet_name` | Subnet name |
| `notification_channel_id` | Monitoring notification channel |

### Using Outputs

```bash
# Get cluster credentials
gcloud container clusters get-credentials \
  $(terraform output -raw cluster_name) \
  --region=$(terraform output -raw region)

# Get artifact registry URL
echo $(terraform output -raw artifact_registry_url)
# Output: us-central1-docker.pkg.dev/compact-orb-498606-f9/security-patch-agent
```

## State Management

### Backend Configuration

Terraform state is stored in Google Cloud Storage:
```hcl
backend "gcs" {
  bucket = "compact-orb-498606-f9-terraform-state"
  prefix = "security-patch-agent"
}
```

### State File Location
```
gs://compact-orb-498606-f9-terraform-state/security-patch-agent/default.tfstate
```

### Accessing State

```bash
# List state resources
terraform state list

# Show specific resource
terraform state show google_container_cluster.primary[0]

# Pull current state
terraform state pull > current-state.json
```

### State Locking

Terraform automatically locks state during operations. If a lock persists:

```bash
# Force unlock (use with caution)
terraform force-unlock LOCK_ID
```

## Modifying Infrastructure

### Add a new GCP resource

1. Edit `main.tf`:
   ```hcl
   resource "google_compute_address" "static_ip" {
     name   = "security-patch-agent-ip"
     region = var.region
   }
   ```

2. Update outputs in `outputs.tf`:
   ```hcl
   output "static_ip_address" {
     value = google_compute_address.static_ip.address
   }
   ```

3. Apply changes:
   ```bash
   terraform plan
   terraform apply
   ```

### Change existing resource

Example: Update cluster maintenance window

```hcl
# In main.tf, update:
maintenance_policy {
  daily_maintenance_window {
    start_time = "02:00"  # Changed from 03:00
  }
}
```

```bash
terraform plan  # Review changes
terraform apply
```

### Import existing resources

If resources exist outside Terraform:

```bash
# Example: Import existing cluster
terraform import 'google_container_cluster.primary[0]' \
  projects/compact-orb-498606-f9/locations/us-central1/clusters/code-vulnerability-scanner
```

## Destroying Infrastructure

### Destroy all resources

```bash
terraform destroy -var="components=all"
```

### Destroy specific components

```bash
# Remove only monitoring
terraform destroy -var="components=monitoring-only"
```

### Via GitHub Actions

1. Go to **Actions** → **Deploy Infrastructure**
2. Click **Run workflow**
3. Select:
   - Action: `destroy`
   - Components: what to destroy

⚠️ **Warning**: This is destructive and irreversible!

## Best Practices

### ✅ DO

- Always run `terraform plan` before `apply`
- Use workspaces for multiple environments
- Enable state file versioning (already enabled)
- Use variables for environment-specific values
- Tag resources for cost tracking
- Keep provider versions pinned

### ❌ DON'T

- Manually modify resources created by Terraform
- Share state files (use remote backend)
- Commit `.tfstate` files to git
- Use `terraform apply` without reviewing plan
- Skip running `terraform init` after changes

## Cost Management

### Estimate costs before applying

```bash
# Install terraform cost estimation tool
brew install infracost

# Generate cost estimate
infracost breakdown --path .
```

### Track costs

```bash
# View current infrastructure cost
gcloud billing projects describe compact-orb-498606-f9 \
  --format="value(billingAccountName)"
```

## Troubleshooting

### Error: Backend initialization required

```bash
cd infrastructure/terraform
terraform init -reconfigure
```

### Error: Resource already exists

```bash
# Import the existing resource
terraform import google_artifact_registry_repository.docker_repo[0] \
  projects/compact-orb-498606-f9/locations/us-central1/repositories/security-patch-agent
```

### Error: Insufficient permissions

Ensure service account has:
- `roles/owner` OR
- `roles/editor` + `roles/compute.admin` + `roles/container.admin`

### Error: API not enabled

```bash
gcloud services enable container.googleapis.com \
  --project=compact-orb-498606-f9
```

### Error: State lock timeout

Another operation is in progress. Wait or force unlock:
```bash
terraform force-unlock <LOCK_ID>
```

## Upgrading Terraform

### Update provider versions

```bash
# Update providers to latest within version constraints
terraform init -upgrade

# Update Terraform version
tfenv install 1.7.5
tfenv use 1.7.5
```

### Migrate state to new version

```bash
# Backup current state
terraform state pull > backup-$(date +%Y%m%d).tfstate

# Upgrade
terraform init -upgrade
terraform plan  # Verify no unexpected changes
```

## Advanced Usage

### Multiple Environments

Create workspaces:
```bash
terraform workspace new dev
terraform workspace new staging
terraform workspace new production

# Switch workspace
terraform workspace select production

# Apply to specific workspace
terraform apply -var="components=all"
```

### Custom Variables File

```bash
# Create terraform.tfvars
cat > terraform.tfvars <<EOF
project_id = "my-project"
region     = "us-west1"
cluster_name = "my-cluster"
alert_email = "me@example.com"
EOF

terraform apply
```

### Module Usage (Future)

```hcl
# Use as a module
module "security_patch_agent" {
  source = "./infrastructure/terraform"
  
  project_id = "my-project"
  region     = "us-east1"
}
```

## Further Reading

- [Terraform GCP Provider Docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [GKE Terraform Examples](https://github.com/terraform-google-modules/terraform-google-kubernetes-engine)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)
