# BigQuery Dataset for Security Scans
resource "google_bigquery_dataset" "security_scans" {
  dataset_id  = "security_scans"
  location    = var.region
  description = "Security scan results, vulnerabilities, patches, and outcomes"

  labels = {
    environment = "production"
    app         = "security-patch-agent"
  }

  # Grant dataset owner permissions to service account
  access {
    role          = "OWNER"
    user_by_email = google_service_account.app_sa[0].email
  }

  # Grant owner to the user running terraform
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  depends_on = [google_project_service.required_apis]
}

# Table 1: Scans (main table with scan metadata)
resource "google_bigquery_table" "scans" {
  dataset_id = google_bigquery_dataset.security_scans.dataset_id
  table_id   = "scans"

  deletion_protection = false # Set to true in production

  # Partition by day for efficient time-based queries
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  # Cluster by repo and mode for fast lookups
  clustering = ["repo_name", "scan_mode"]

  schema = jsonencode([
    { name = "scan_id", type = "STRING", mode = "REQUIRED" },
    { name = "timestamp", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "repo_url", type = "STRING", mode = "REQUIRED" },
    { name = "repo_name", type = "STRING", mode = "REQUIRED" },
    { name = "repo_owner", type = "STRING" },
    { name = "branch", type = "STRING" },
    { name = "commit_sha", type = "STRING" },
    { name = "scan_mode", type = "STRING", mode = "REQUIRED" }, # review or patch
    { name = "status", type = "STRING" },                        # running, completed, failed
    { name = "trigger_type", type = "STRING" },                  # api, pr_event, scheduled

    # Results
    { name = "vulnerabilities_found", type = "INTEGER" },
    { name = "fixes_applied", type = "INTEGER" },
    { name = "pr_url", type = "STRING" },
    { name = "pr_number", type = "INTEGER" },
    { name = "pr_merged", type = "BOOLEAN" },
    { name = "pr_merge_date", type = "TIMESTAMP" },
    { name = "evidence_path", type = "STRING" }, # GCS link to detailed evidence

    # Performance
    { name = "duration_seconds", type = "INTEGER" },
    { name = "phase_durations", type = "STRING" }, # JSON

    # LLM Context (KEY INNOVATION)
    { name = "findings_summary", type = "STRING" },       # JSON array
    { name = "patches_summary", type = "STRING" },        # JSON array
    { name = "llm_model_used", type = "STRING" },         # gemini-3.1-pro
    { name = "llm_tokens_used", type = "INTEGER" },       # Cost tracking
    { name = "llm_context_included", type = "BOOLEAN" },  # Was history provided?
    { name = "llm_context_scan_ids", type = "STRING" },   # Which past scans in context
  ])
}

# Table 2: Vulnerabilities (detailed findings with evidence tiers)
resource "google_bigquery_table" "vulnerabilities" {
  dataset_id = google_bigquery_dataset.security_scans.dataset_id
  table_id   = "vulnerabilities"

  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "discovered_at"
  }

  clustering = ["scan_id", "vulnerability_type", "severity"]

  schema = jsonencode([
    { name = "vulnerability_id", type = "STRING", mode = "REQUIRED" },
    { name = "scan_id", type = "STRING", mode = "REQUIRED" },
    { name = "discovered_at", type = "TIMESTAMP", mode = "REQUIRED" },

    # Vulnerability details
    { name = "vulnerability_type", type = "STRING" },
    { name = "file_path", type = "STRING" },
    { name = "line_number", type = "INTEGER" },
    { name = "severity", type = "STRING" }, # CRITICAL, HIGH, MEDIUM, LOW
    { name = "cvss_score", type = "FLOAT" },
    { name = "cvss_vector", type = "STRING" },
    { name = "cwe_id", type = "STRING" },

    # Evidence Hierarchy (R1 from PANW)
    { name = "verification_level", type = "STRING" }, # LATENT, STATIC, CONFIRMED, E2E
    { name = "source_evidence", type = "STRING" },
    { name = "reach_evidence", type = "STRING" },
    { name = "sink_evidence", type = "STRING" },
    { name = "impact_evidence", type = "STRING" },

    # Fix tracking
    { name = "fixed", type = "BOOLEAN" },
    { name = "fix_applied_in_scan", type = "STRING" },
    { name = "recurrence_count", type = "INTEGER" },
    { name = "first_seen_scan_id", type = "STRING" },

    # Documentation
    { name = "description", type = "STRING" },
    { name = "reproduction_steps", type = "STRING" },
    { name = "remediation_advice", type = "STRING" },
  ])
}

# Table 3: Patches (generated fixes with LLM reasoning)
resource "google_bigquery_table" "patches" {
  dataset_id = google_bigquery_dataset.security_scans.dataset_id
  table_id   = "patches"

  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "applied_at"
  }

  clustering = ["scan_id", "vulnerability_type"]

  schema = jsonencode([
    { name = "patch_id", type = "STRING", mode = "REQUIRED" },
    { name = "scan_id", type = "STRING", mode = "REQUIRED" },
    { name = "vulnerability_id", type = "STRING" },
    { name = "applied_at", type = "TIMESTAMP", mode = "REQUIRED" },

    # Patch details
    { name = "file_path", type = "STRING" },
    { name = "vulnerability_type", type = "STRING" },
    { name = "original_code", type = "STRING" },
    { name = "patched_code", type = "STRING" },
    { name = "diff", type = "STRING" },
    { name = "lines_changed", type = "INTEGER" },

    # LLM reasoning
    { name = "reasoning", type = "STRING" },
    { name = "alternatives_considered", type = "STRING" },
    { name = "confidence", type = "STRING" }, # HIGH, MEDIUM, LOW

    # Validation
    { name = "validation_status", type = "STRING" },
    { name = "test_results", type = "STRING" },

    # Outcome tracking
    { name = "accepted", type = "BOOLEAN" },
    { name = "modified_before_merge", type = "BOOLEAN" },
    { name = "rejection_reason", type = "STRING" },
  ])
}

# Table 4: Scan Outcomes (for learning from PR results)
resource "google_bigquery_table" "scan_outcomes" {
  dataset_id = google_bigquery_dataset.security_scans.dataset_id
  table_id   = "scan_outcomes"

  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "outcome_date"
  }

  clustering = ["scan_id"]

  schema = jsonencode([
    { name = "outcome_id", type = "STRING", mode = "REQUIRED" },
    { name = "scan_id", type = "STRING", mode = "REQUIRED" },
    { name = "outcome_date", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "outcome_type", type = "STRING" }, # merged, rejected, modified, abandoned
    { name = "pr_review_comments", type = "STRING" },
    { name = "rejection_reason", type = "STRING" },
    { name = "modifications_made", type = "STRING" },
    { name = "time_to_merge_hours", type = "FLOAT" },
    { name = "reviewer", type = "STRING" },
    { name = "notes", type = "STRING" },
  ])
}

# Grant BigQuery permissions to service account
resource "google_project_iam_member" "app_sa_bq_data_editor" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.app_sa[0].email}"
}

resource "google_project_iam_member" "app_sa_bq_job_user" {
  count = var.components == "all" || var.components == "gke-only" ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.app_sa[0].email}"
}
