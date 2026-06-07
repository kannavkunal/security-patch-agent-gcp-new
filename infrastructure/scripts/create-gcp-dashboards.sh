#!/bin/bash
set -e

PROJECT_ID="compact-orb-498606-f9"

echo "================================================"
echo "Creating Cloud Monitoring Dashboards"
echo "================================================"
echo ""

# Create custom dashboard for Security Patch Agent
echo "Creating Security Patch Agent dashboard..."

gcloud monitoring dashboards create --config-from-file=- <<EOF
{
  "displayName": "Security Patch Agent - Production Metrics",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Request Rate (req/min)",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              }
            }],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "requests/min",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "xPos": 6,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Response Time (95th percentile)",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"istio.io/service/server/response_latencies\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_DELTA",
                    "crossSeriesReducer": "REDUCE_PERCENTILE_95"
                  }
                }
              }
            }],
            "yAxis": {
              "label": "milliseconds"
            }
          }
        }
      },
      {
        "yPos": 4,
        "width": 4,
        "height": 4,
        "widget": {
          "title": "Success Rate",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"istio.io/service/server/request_count\" metric.labels.response_code!~\"5.*\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_RATE"
                }
              }
            },
            "gaugeView": {
              "lowerBound": 0,
              "upperBound": 100
            }
          }
        }
      },
      {
        "xPos": 4,
        "yPos": 4,
        "width": 4,
        "height": 4,
        "widget": {
          "title": "Error Rate (5xx)",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"istio.io/service/server/request_count\" metric.labels.response_code=~\"5.*\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_RATE"
                }
              }
            },
            "thresholds": [{
              "value": 1,
              "color": "YELLOW"
            }, {
              "value": 5,
              "color": "RED"
            }]
          }
        }
      },
      {
        "xPos": 8,
        "yPos": 4,
        "width": 4,
        "height": 4,
        "widget": {
          "title": "Active Pods",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"k8s_pod\" resource.labels.namespace_name=\"security-patch-agent\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "crossSeriesReducer": "REDUCE_COUNT"
                }
              }
            }
          }
        }
      },
      {
        "yPos": 8,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "CPU Usage by Container",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"kubernetes.io/container/cpu/core_usage_time\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "xPos": 6,
        "yPos": 8,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Memory Usage by Container",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"kubernetes.io/container/memory/used_bytes\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "yPos": 12,
        "width": 12,
        "height": 4,
        "widget": {
          "title": "HTTP Status Codes Distribution",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"istio.io/service/server/request_count\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE",
                    "crossSeriesReducer": "REDUCE_SUM",
                    "groupByFields": ["metric.response_code"]
                  }
                }
              }
            }],
            "chartOptions": {
              "mode": "COLOR"
            }
          }
        }
      },
      {
        "yPos": 16,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Rate Limited Requests (429)",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"istio.io/service/server/request_count\" metric.labels.response_code=\"429\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "xPos": 6,
        "yPos": 16,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Unauthorized Requests (401/403)",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"k8s_container\" resource.labels.namespace_name=\"security-patch-agent\" metric.type=\"istio.io/service/server/request_count\" metric.labels.response_code=~\"40[13]\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE",
                    "crossSeriesReducer": "REDUCE_SUM",
                    "groupByFields": ["metric.response_code"]
                  }
                }
              }
            }]
          }
        }
      }
    ]
  }
}
EOF

echo "✅ Dashboard created successfully!"
echo ""
echo "================================================"
echo "View Your Dashboard:"
echo "================================================"
echo ""
echo "🔗 https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
echo ""
echo "Look for: 'Security Patch Agent - Production Metrics'"
echo ""
