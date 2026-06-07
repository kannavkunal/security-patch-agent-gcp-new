# GCS Bucket for Security Evidence Storage
resource "google_storage_bucket" "evidence_bucket" {
  name          = "security-patch-evidence-${var.project_id}"
  location      = var.region
  project       = var.project_id
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    app         = "security-patch-agent"
    environment = "production"
  }

  depends_on = [google_project_service.required_apis]
}

# Grant write access to the service account
resource "google_storage_bucket_iam_member" "evidence_writer" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  bucket = google_storage_bucket.evidence_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.app_sa[0].email}"
}

# Output the bucket name
output "evidence_bucket_name" {
  value       = google_storage_bucket.evidence_bucket.name
  description = "GCS bucket for storing security scan evidence"
}
