# GCS Bucket for Security Evidence Storage (reference existing bucket)
data "google_storage_bucket" "evidence_bucket" {
  name = "security-patch-evidence-${var.project_id}"
}

# Grant write access to the service account
resource "google_storage_bucket_iam_member" "evidence_writer" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  bucket = data.google_storage_bucket.evidence_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.app_sa[0].email}"
}

# Output the bucket name
output "evidence_bucket_name" {
  value       = data.google_storage_bucket.evidence_bucket.name
  description = "GCS bucket for storing security scan evidence"
}
