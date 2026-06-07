# GCP Monitoring Dashboards and Alerts for Security Patch Agent

# Log-based Metrics
# ==================

# Metric 1: Scan completion rate
resource "google_logging_metric" "scan_completed" {
  name   = "security_patch_agent_scans_completed"
  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.namespace_name="security-patch-agent"
    textPayload=~"Scan .* completed"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "scan_mode"
      value_type  = "STRING"
      description = "patch or review"
    }
  }

  label_extractors = {
    "scan_mode" = "EXTRACT(textPayload)"
  }
}

# Metric 2: Scan failures
resource "google_logging_metric" "scan_failed" {
  name   = "security_patch_agent_scans_failed"
  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.namespace_name="security-patch-agent"
    textPayload=~"Scan failed"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# Metric 3: PR creation success
resource "google_logging_metric" "pr_created" {
  name   = "security_patch_agent_prs_created"
  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.namespace_name="security-patch-agent"
    textPayload=~"Created PR"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# Metric 4: Phase 8 evidence generation
resource "google_logging_metric" "evidence_generated" {
  name   = "security_patch_agent_evidence_generated"
  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.namespace_name="security-patch-agent"
    textPayload=~"Evidence uploaded"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# Metric 5: API request rate
resource "google_logging_metric" "api_requests" {
  name   = "security_patch_agent_api_requests"
  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.container_name="api"
    resource.labels.namespace_name="security-patch-agent"
    httpRequest.requestUrl!=""
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key         = "status_code"
      value_type  = "INT64"
      description = "HTTP status code"
    }
    labels {
      key         = "endpoint"
      value_type  = "STRING"
      description = "API endpoint"
    }
  }

  label_extractors = {
    "status_code" = "EXTRACT(httpRequest.status)"
    "endpoint"    = "EXTRACT(httpRequest.requestUrl)"
  }
}

# Dashboard 1: Service Overview
# ==============================

resource "google_monitoring_dashboard" "service_overview" {
  dashboard_json = jsonencode({
    displayName = "Security Patch Agent - Service Overview"
    mosaicLayout = {
      columns = 12
      tiles = [
        # Row 1: Key Metrics
        {
          width  = 4
          height = 4
          xPos   = 0
          yPos   = 0
          widget = {
            title = "Total Scans (24h)"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.scan_completed.name}\""
                  aggregation = {
                    alignmentPeriod  = "86400s"
                    perSeriesAligner = "ALIGN_SUM"
                  }
                }
              }
            }
          }
        },
        {
          width  = 4
          height = 4
          xPos   = 4
          yPos   = 0
          widget = {
            title = "PRs Created (24h)"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.pr_created.name}\""
                  aggregation = {
                    alignmentPeriod  = "86400s"
                    perSeriesAligner = "ALIGN_SUM"
                  }
                }
              }
            }
          }
        },
        {
          width  = 4
          height = 4
          xPos   = 8
          yPos   = 0
          widget = {
            title = "Failed Scans (24h)"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.scan_failed.name}\""
                  aggregation = {
                    alignmentPeriod  = "86400s"
                    perSeriesAligner = "ALIGN_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_BAR"
              }
            }
          }
        },

        # Row 2: API Performance
        {
          width  = 6
          height = 4
          yPos   = 4
          widget = {
            title = "API Request Rate"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.api_requests.name}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.endpoint"]
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 4
          widget = {
            title = "API Response Codes"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.api_requests.name}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.status_code"]
                    }
                  }
                }
                plotType = "STACKED_BAR"
              }]
            }
          }
        },

        # Row 3: Pod Health
        {
          width  = 6
          height = 4
          yPos   = 8
          widget = {
            title = "Pod CPU Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"kubernetes.io/container/cpu/core_usage_time\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.container_name"]
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 8
          widget = {
            title = "Pod Memory Usage (GB)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"kubernetes.io/container/memory/used_bytes\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.container_name"]
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },

        # Row 4: Pub/Sub
        {
          width  = 6
          height = 4
          yPos   = 12
          widget = {
            title = "Pub/Sub Messages Published"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"pubsub_topic\" resource.labels.topic_id=\"${google_pubsub_topic.security_scan_events.name}\" metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 12
          widget = {
            title = "Pub/Sub Undelivered Messages"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"pubsub_subscription\" metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Messages"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
}

# Dashboard 2: BigQuery Analytics
# ================================

resource "google_monitoring_dashboard" "bigquery_analytics" {
  dashboard_json = jsonencode({
    displayName = "Security Patch Agent - BigQuery Analytics"
    mosaicLayout = {
      columns = 12
      tiles = [
        # Scans by Mode
        {
          width  = 6
          height = 4
          widget = {
            title = "Scans by Mode (Last 7 Days)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.scan_completed.name}\""
                    aggregation = {
                      alignmentPeriod    = "3600s"
                      perSeriesAligner   = "ALIGN_SUM"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.scan_mode"]
                    }
                  }
                }
                plotType = "STACKED_AREA"
              }]
            }
          }
        },
        # Evidence Generation Rate
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Evidence Generation Success Rate"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.evidence_generated.name}\""
                    aggregation = {
                      alignmentPeriod  = "3600s"
                      perSeriesAligner = "ALIGN_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        # BigQuery Query Count
        {
          width  = 6
          height = 4
          yPos   = 4
          widget = {
            title = "BigQuery Query Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"global\" metric.type=\"bigquery.googleapis.com/query/count\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        # BigQuery Bytes Billed
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 4
          widget = {
            title = "BigQuery Data Processed (GB)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"global\" metric.type=\"bigquery.googleapis.com/query/scanned_bytes\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        }
      ]
    }
  })
}

# Dashboard 3: Scan Pipeline Performance
# =======================================

resource "google_monitoring_dashboard" "scan_pipeline" {
  dashboard_json = jsonencode({
    displayName = "Security Patch Agent - Scan Pipeline"
    mosaicLayout = {
      columns = 12
      tiles = [
        # Job Success/Failure
        {
          width  = 6
          height = 4
          xPos   = 0
          yPos   = 0
          widget = {
            title = "Scan Job Completion"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.scan_completed.name}\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType       = "LINE"
                  targetAxis     = "Y1"
                  legendTemplate = "Completed"
                },
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.scan_failed.name}\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType       = "LINE"
                  targetAxis     = "Y1"
                  legendTemplate = "Failed"
                }
              ]
            }
          }
        },
        # K8s Job Count
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 0
          widget = {
            title = "Active K8s Jobs"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"k8s_pod\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"kubernetes.io/pod/volume/used_bytes\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_COUNT"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        }
      ]
    }
  })
}

# Alerting Policies
# =================

# Alert 1: High scan failure rate
resource "google_monitoring_alert_policy" "high_scan_failure_rate" {
  display_name = "Security Patch Agent - High Scan Failure Rate"
  combiner     = "OR"

  depends_on = [
    google_logging_metric.scan_failed,
    time_sleep.wait_for_metrics,  # Wait for metric propagation
  ]

  conditions {
    display_name = "Scan failure rate > 20%"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.scan_failed.name}\" resource.type=\"k8s_container\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "Scan failure rate is elevated. Check logs for errors in the security-patch-agent namespace."
    mime_type = "text/markdown"
  }
}

# Alert 2: API errors
resource "google_monitoring_alert_policy" "api_error_rate" {
  display_name = "Security Patch Agent - API Error Rate High"
  combiner     = "OR"

  depends_on = [
    google_logging_metric.api_requests,
    time_sleep.wait_for_metrics,  # Wait for metric propagation
  ]

  conditions {
    display_name = "5xx errors > 10/min"

    condition_threshold {
      filter          = "resource.type=\"k8s_container\" metric.type=\"logging.googleapis.com/user/${google_logging_metric.api_requests.name}\" metric.label.status_code>=500"
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  documentation {
    content   = "API is returning elevated 5xx errors. Check API pod logs and dependencies (Vertex AI, BigQuery, Secret Manager)."
    mime_type = "text/markdown"
  }
}

# Alert 3: Pub/Sub backlog
resource "google_monitoring_alert_policy" "pubsub_backlog" {
  display_name = "Security Patch Agent - Pub/Sub Backlog"
  combiner     = "OR"

  conditions {
    display_name = "Undelivered messages > 50"

    condition_threshold {
      filter          = "resource.type=\"pubsub_subscription\" metric.type=\"pubsub.googleapis.com/subscription/num_undelivered_messages\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 50

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = []

  documentation {
    content   = "Pub/Sub has a backlog of undelivered messages. Worker may be down or overloaded. Check worker pod status."
    mime_type = "text/markdown"
  }
}

# Outputs
output "dashboard_links" {
  value = {
    service_overview   = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.service_overview.id}?project=${var.project_id}"
    bigquery_analytics = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.bigquery_analytics.id}?project=${var.project_id}"
    scan_pipeline      = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.scan_pipeline.id}?project=${var.project_id}"
  }
  description = "Links to Cloud Monitoring dashboards"
}
