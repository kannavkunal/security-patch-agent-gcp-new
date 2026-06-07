# Time delay to allow logging metrics to propagate in GCP
# Logging metrics can take up to 10 minutes to become available
# for use in alert policies and dashboards

resource "time_sleep" "wait_for_metrics" {
  depends_on = [
    google_logging_metric.scan_completed,
    google_logging_metric.scan_failed,
    google_logging_metric.pr_created,
    google_logging_metric.evidence_generated,
    google_logging_metric.api_requests,
  ]

  create_duration = "120s"  # Wait 2 minutes for metrics to propagate

  triggers = {
    # Force recreation if any metric changes
    metrics = join(",", [
      google_logging_metric.scan_completed.id,
      google_logging_metric.scan_failed.id,
      google_logging_metric.pr_created.id,
      google_logging_metric.evidence_generated.id,
      google_logging_metric.api_requests.id,
    ])
  }
}
