"""Pub/Sub Worker - Listens for scan events and spawns K8s Jobs"""
import os
import json
import logging
import re
from typing import Tuple
from google.cloud import pubsub_v1
from concurrent import futures
from app.job_spawner import JobSpawner

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROJECT_ID = os.getenv("GCP_PROJECT_ID")
if not PROJECT_ID:
    raise ValueError("GCP_PROJECT_ID environment variable must be set")
SUBSCRIPTION_ID = os.getenv("PUBSUB_SUBSCRIPTION", "scan-events-subscription")

# Whitelist of allowed repositories (must match main.py)
ALLOWED_REPOS = [
    "https://github.com/kannavkunal/vulnerable-python-api",
    "https://github.com/kannavkunal/vulnerable-java-app",
    "https://github.com/kannavkunal/vulnerable-node-service",
    "https://github.com/kannavkunal/vulnerable-go-microservice"
]


def validate_message(data: dict) -> Tuple[bool, str]:
    """
    Strict message validation with type checking and format validation

    Returns:
        (is_valid, error_message)
    """
    # Required fields with type checking
    required_fields = {
        "scan_id": str,
        "repo_url": str,
        "mode": str,
        "branch": str
    }

    # Check required fields exist and have correct type
    for field, expected_type in required_fields.items():
        if field not in data:
            return False, f"Missing required field: {field}"
        if not isinstance(data[field], expected_type):
            return False, f"Field '{field}' must be of type {expected_type.__name__}, got {type(data[field]).__name__}"
        if not data[field]:  # Check for empty strings
            return False, f"Field '{field}' cannot be empty"

    # Validate scan_id format
    if not re.match(r'^scan-[a-f0-9-]{36}$', data["scan_id"]):
        return False, f"Invalid scan_id format: {data['scan_id']}"

    # Validate mode (must be "patch" or "review")
    if data["mode"] not in ["patch", "review"]:
        return False, f"Invalid mode: {data['mode']}. Must be 'patch' or 'review'"

    # Validate repo_url format
    repo_url = data["repo_url"].rstrip('/')
    if not re.match(r'^https://github\.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$', repo_url):
        return False, f"Invalid repo_url format: {repo_url}"

    # Validate repo_url against whitelist
    if repo_url not in ALLOWED_REPOS:
        return False, f"Repository not in whitelist: {repo_url}. Allowed: {', '.join(ALLOWED_REPOS)}"

    # Validate branch name
    branch = data["branch"]
    if len(branch) > 255:
        return False, f"Branch name too long: {len(branch)} chars (max 255)"
    if '../' in branch or branch.startswith('/') or branch.startswith('.'):
        return False, f"Invalid branch name (path traversal detected): {branch}"
    if not re.match(r'^[a-zA-Z0-9/_.-]+$', branch):
        return False, f"Branch name contains invalid characters: {branch}"

    # For review mode, pr_number is required and must be integer
    if data["mode"] == "review":
        if "pr_number" not in data:
            return False, "pr_number is required for review mode"
        if not isinstance(data["pr_number"], int):
            return False, f"pr_number must be integer, got {type(data['pr_number']).__name__}"
        if data["pr_number"] <= 0:
            return False, f"pr_number must be positive, got {data['pr_number']}"

    # Validate trigger_type if present
    if "trigger_type" in data:
        if data["trigger_type"] not in ["api", "webhook"]:
            return False, f"Invalid trigger_type: {data['trigger_type']}. Must be 'api' or 'webhook'"

    return True, "OK"


def callback(message: pubsub_v1.subscriber.message.Message):
    """
    Process incoming Pub/Sub messages and spawn K8s Jobs

    Message format:
    {
        "scan_id": "scan-uuid",
        "repo_url": "https://github.com/user/repo",
        "mode": "patch" or "review",
        "branch": "main",
        "trigger_type": "api" or "webhook",
        "pr_number": 123 (optional, for review mode)
    }
    """
    try:
        # Parse message
        data = json.loads(message.data.decode("utf-8"))
        logger.info(f"Received scan request: {data}")

        # Strict validation
        is_valid, error_msg = validate_message(data)
        if not is_valid:
            logger.error(f"Invalid message rejected: {error_msg} | Message: {data}")
            # ACK invalid messages (don't retry them)
            message.ack()
            return

        scan_id = data["scan_id"]
        repo_url = data["repo_url"].rstrip('/')  # Normalize URL
        mode = data["mode"]
        branch = data["branch"]
        pr_number = data.get("pr_number")  # Optional, only for review mode

        logger.info(f"Creating job for scan_id={scan_id}, repo={repo_url}, mode={mode}, branch={branch}")

        # Create K8s Job
        spawner = JobSpawner()
        job_name = spawner.create_scan_job(
            scan_id=scan_id,
            repo_url=repo_url,
            mode=mode,
            branch=branch,
            pr_number=pr_number
        )

        logger.info(f"Successfully created job {job_name} for scan {scan_id}")

        # Acknowledge message
        message.ack()

    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse message as JSON: {e}")
        # ACK invalid JSON (don't retry)
        message.ack()
    except Exception as e:
        logger.error(f"Error processing message: {e}", exc_info=True)
        # NACK the message so it can be retried (infrastructure errors, etc.)
        message.nack()


def main():
    """Start the Pub/Sub worker"""
    logger.info(f"Starting Pub/Sub worker for {PROJECT_ID}/{SUBSCRIPTION_ID}")

    subscriber = pubsub_v1.SubscriberClient()
    subscription_path = subscriber.subscription_path(PROJECT_ID, SUBSCRIPTION_ID)

    # Configure streaming pull
    streaming_pull_future = subscriber.subscribe(
        subscription_path,
        callback=callback,
        flow_control=pubsub_v1.types.FlowControl(
            max_messages=10,  # Process up to 10 concurrent scans
            max_lease_duration=600  # 10 minute timeout per message
        )
    )

    logger.info(f"Listening for messages on {subscription_path}")

    # Keep the worker running
    try:
        streaming_pull_future.result()
    except KeyboardInterrupt:
        logger.info("Shutting down worker...")
        streaming_pull_future.cancel()
        streaming_pull_future.result()


if __name__ == "__main__":
    main()
