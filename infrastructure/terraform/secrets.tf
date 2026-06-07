# Secret Manager for GitHub Token
#
# Note: Gemini/Vertex AI authentication uses Workload Identity automatically
# (service account already has roles/aiplatform.user permission)
# No API key needed!

# Enable Secret Manager API
resource "google_project_service" "secretmanager_api" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Secret: GitHub Personal Access Token (import existing)
# terraform import google_secret_manager_secret.github_token projects/compact-orb-498606-f9/secrets/github-token
resource "google_secret_manager_secret" "github_token" {
  secret_id = "github-token"

  replication {
    auto {}
  }

  labels = {
    environment = "production"
    app         = "security-patch-agent"
    type        = "github-credentials"
  }

  lifecycle {
    ignore_changes = [replication]
  }

  depends_on = [google_project_service.secretmanager_api]
}

# Secret: GitHub Webhook Secret
# Used for:
# - Verifying webhook signatures from GitHub
# - Ensuring webhooks are authentic
resource "google_secret_manager_secret" "github_webhook_secret" {
  secret_id = "github-webhook-secret"

  replication {
    auto {}
  }

  labels = {
    environment = "production"
    app         = "security-patch-agent"
    type        = "webhook-secret"
  }

  depends_on = [google_project_service.secretmanager_api]
}

# IAM: Grant Workload Identity access to GitHub token
resource "google_secret_manager_secret_iam_member" "github_token_access" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  secret_id = google_secret_manager_secret.github_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.k8s_service_account}]"
}

# IAM: Grant GCP Service Account access (for Kubernetes Jobs)
resource "google_secret_manager_secret_iam_member" "github_token_sa_access" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  secret_id = google_secret_manager_secret.github_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app_sa[0].email}"
}

# IAM: Grant Workload Identity access to webhook secret
resource "google_secret_manager_secret_iam_member" "webhook_secret_access" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  secret_id = google_secret_manager_secret.github_webhook_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.k8s_service_account}]"
}

# IAM: Grant GCP Service Account access to webhook secret
resource "google_secret_manager_secret_iam_member" "webhook_secret_sa_access" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  secret_id = google_secret_manager_secret.github_webhook_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app_sa[0].email}"
}

# Instructions Output
output "secret_setup_instructions" {
  value = <<-EOT

  📝 SECRET SETUP INSTRUCTIONS

  After terraform apply completes, add your secrets:

  1. Create GitHub Personal Access Token:
     - Go to: https://github.com/settings/tokens/new
     - Select scopes:
       ✅ repo (full control of private repositories)
       ✅ workflow (update GitHub Action workflows)
       ✅ write:packages (upload packages)
     - Generate and copy the token

  2. Store GitHub token in Secret Manager:
     echo "your_github_token_here" | gcloud secrets versions add github-token --data-file=-

  3. Generate and store webhook secret (for GitHub webhook signature verification):
     # Generate a random secret
     openssl rand -hex 32 > /tmp/webhook-secret.txt

     # Store it
     cat /tmp/webhook-secret.txt | gcloud secrets versions add github-webhook-secret --data-file=-

     # Copy this value - you'll need it when configuring GitHub webhooks
     cat /tmp/webhook-secret.txt
     rm /tmp/webhook-secret.txt

  4. Verify secrets:
     gcloud secrets versions access latest --secret="github-token"
     gcloud secrets versions access latest --secret="github-webhook-secret"

  5. Configure GitHub Webhooks (for each vulnerable test repo):
     - Go to: https://github.com/YOUR_USERNAME/REPO_NAME/settings/hooks
     - Add webhook:
       - Payload URL: https://YOUR_LOADBALANCER_IP/webhook/github
       - Content type: application/json
       - Secret: (paste webhook secret from step 3)
       - Events: Pull requests
       - Active: ✅

  Note: Vertex AI authentication uses Workload Identity (already configured)
        No API key needed - service account has roles/aiplatform.user

  EOT
}
