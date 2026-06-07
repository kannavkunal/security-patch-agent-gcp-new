# Pub/Sub Topic for Security Scan Events
resource "google_pubsub_topic" "security_scan_events" {
  name = "security-scan-events"

  message_retention_duration = "86400s" # 24 hours

  labels = {
    environment = "production"
    app         = "security-patch-agent"
  }

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub Subscription for orchestrator service
resource "google_pubsub_subscription" "scan_events_sub" {
  name  = "scan-events-subscription"
  topic = google_pubsub_topic.security_scan_events.name

  # Acknowledgement deadline
  ack_deadline_seconds = 300 # 5 minutes for long-running scans

  # Message retention
  message_retention_duration = "86400s" # 24 hours

  # Retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s" # 10 minutes
  }

  # Dead letter policy (after 5 failures, send to DLQ)
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  # Enable exactly-once delivery
  enable_exactly_once_delivery = true

  labels = {
    environment = "production"
    app         = "security-patch-agent"
  }
}

# Dead Letter Topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name = "security-scan-events-dlq"

  message_retention_duration = "604800s" # 7 days

  labels = {
    environment = "production"
    app         = "security-patch-agent"
    type        = "dead-letter-queue"
  }
}

# Dead Letter Subscription (for monitoring/debugging)
resource "google_pubsub_subscription" "dead_letter_sub" {
  name  = "scan-events-dlq-subscription"
  topic = google_pubsub_topic.dead_letter.name

  # Keep messages for investigation
  message_retention_duration = "604800s" # 7 days
  ack_deadline_seconds       = 600       # 10 minutes

  labels = {
    environment = "production"
    app         = "security-patch-agent"
  }
}

# IAM: Allow service account to publish to topic
resource "google_pubsub_topic_iam_member" "publisher" {
  topic  = google_pubsub_topic.security_scan_events.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.app_sa[0].email}"
}

# IAM: Allow service account to subscribe
resource "google_pubsub_subscription_iam_member" "subscriber" {
  subscription = google_pubsub_subscription.scan_events_sub.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.app_sa[0].email}"
}
