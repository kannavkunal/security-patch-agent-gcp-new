"""Phase 7: Audit Logging to BigQuery"""
from .base import Phase
from typing import Dict, Any
from app.clients.bq_client import BigQueryClient
from datetime import datetime
import json

class Phase7Logger(Phase):
    def execute(self) -> Dict[str, Any]:
        self.logger.info("Phase 7: Logging to BigQuery")

        try:
            client = BigQueryClient()

            # Extract repo owner from repo_name (owner/repo)
            repo_name = self.context.get("repo_name", "")
            repo_owner = repo_name.split("/")[0] if "/" in repo_name else None

            # Prepare vulnerability and patch summaries
            vulnerabilities = self.context.get("vulnerabilities", [])
            patches = self.context.get("patches", [])

            findings_summary = json.dumps([
                {
                    "type": v.get("type"),
                    "severity": v.get("severity"),
                    "file": v.get("file", "").split("/")[-1],
                    "line": v.get("line")
                }
                for v in vulnerabilities[:10]  # Top 10
            ]) if vulnerabilities else None

            patches_summary = json.dumps([
                {
                    "file": p.get("file_path"),
                    "vulnerability_type": p.get("vulnerability_type")
                }
                for p in patches[:10]  # Top 10
            ]) if patches else None

            # Construct pr_url if we have pr_number but not pr_url (REVIEW mode)
            pr_url = self.context.get("pr_url")
            pr_number = self.context.get("pr_number")
            if not pr_url and pr_number and repo_name:
                pr_url = f"https://github.com/{repo_name}/pull/{pr_number}"

            # Prepare scan data
            scan_data = {
                "scan_id": self.context.get("scan_id"),
                "timestamp": datetime.utcnow().isoformat(),
                "repo_url": self.context.get("repo_url"),
                "repo_name": repo_name,
                "repo_owner": repo_owner,
                "branch": self.context.get("branch", "main"),
                "commit_sha": None,  # Would need to get from git
                "scan_mode": self.context.get("scan_mode"),
                "status": "completed",
                "trigger_type": self.context.get("trigger_type", "api"),

                # Results
                "vulnerabilities_found": len(vulnerabilities),
                "fixes_applied": len(patches),
                "pr_url": pr_url,
                "pr_number": pr_number,
                "pr_merged": None,  # Would need webhook to track
                "pr_merge_date": None,
                "evidence_path": self.context.get("evidence_path", ""),

                # Performance (not tracked yet)
                "duration_seconds": None,
                "phase_durations": None,

                # LLM Context
                "findings_summary": findings_summary,
                "patches_summary": patches_summary,
                "llm_model_used": "gemini-2.5-pro",
                "llm_tokens_used": None,  # Would need to track from API responses
                "llm_context_included": self.context.get("llm_context_used", False),
                "llm_context_scan_ids": None  # Would need to pass from Phase 3
            }

            client.log_scan(scan_data)
            self.logger.info("Scan logged to BigQuery")

            return {"logged": True}
        except Exception as e:
            self.logger.error(f"BigQuery logging failed: {e}")
            return {"logged": False, "error": str(e)}
