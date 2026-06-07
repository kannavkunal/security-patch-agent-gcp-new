"""
BigQuery Client - Logging scans, vulnerabilities, and patches
"""
from google.cloud import bigquery
from typing import List, Dict, Any
import json
import logging
import os
from datetime import datetime

logger = logging.getLogger(__name__)


class BigQueryClient:
    """Handles all BigQuery operations for audit logging"""

    def __init__(self, project_id: str = None, dataset_id: str = "security_scans"):
        if project_id is None:
            project_id = os.getenv("GCP_PROJECT_ID")
            if not project_id:
                raise ValueError("GCP_PROJECT_ID environment variable must be set")
        self.client = bigquery.Client(project=project_id)
        self.project_id = project_id
        self.dataset_id = dataset_id

    def log_scan(self, scan_data: Dict[str, Any]) -> None:
        """Log scan metadata to scans table"""
        table_id = f"{self.project_id}.{self.dataset_id}.scans"
        errors = self.client.insert_rows_json(table_id, [scan_data])
        if errors:
            logger.error(f"BigQuery insert failed: {errors}")
            raise Exception(f"Failed to log scan: {errors}")

    def log_vulnerabilities(self, vulnerabilities: List[Dict[str, Any]]) -> None:
        """Log vulnerabilities to vulnerabilities table"""
        if not vulnerabilities:
            return
        table_id = f"{self.project_id}.{self.dataset_id}.vulnerabilities"
        errors = self.client.insert_rows_json(table_id, vulnerabilities)
        if errors:
            logger.error(f"BigQuery insert failed: {errors}")

    def log_patches(self, patches: List[Dict[str, Any]]) -> None:
        """Log patches to patches table"""
        if not patches:
            return
        table_id = f"{self.project_id}.{self.dataset_id}.patches"
        errors = self.client.insert_rows_json(table_id, patches)
        if errors:
            logger.error(f"BigQuery insert failed: {errors}")

    def log_outcome(self, outcome_data: Dict[str, Any]) -> None:
        """Log scan outcome (PR merged/rejected) to scan_outcomes table"""
        table_id = f"{self.project_id}.{self.dataset_id}.scan_outcomes"
        errors = self.client.insert_rows_json(table_id, [outcome_data])
        if errors:
            logger.error(f"BigQuery insert failed: {errors}")
