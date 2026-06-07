"""
Repository Memory System - KEY INNOVATION
Fetches and formats past scan history for LLM context
Enables learning from successful/rejected patches
"""
from google.cloud import bigquery
from typing import List, Dict, Any, Optional
from datetime import datetime
import json
import logging

logger = logging.getLogger(__name__)


class RepoMemory:
    """
    Fetch and format repository scan history for LLM context.

    This is the key differentiator: before analyzing a repository,
    we query BigQuery for the last N scans of that repo and provide
    the LLM with:
    - What vulnerabilities were found
    - What patches were applied
    - Whether PRs were merged, rejected, or modified
    - Why patches were rejected (learn from failures)
    - Recurring issues that weren't fixed

    This allows the LLM to:
    1. Avoid suggesting rejected approaches
    2. Learn coding style from accepted patches
    3. Identify systemic issues (recurring problems)
    4. Be more conservative with high-rejection repos
    """

    def __init__(self, project_id: str, dataset_id: str = "security_scans"):
        self.client = bigquery.Client(project=project_id)
        self.project_id = project_id
        self.dataset_id = dataset_id

    def get_recent_scans(
        self, repo_name: str, limit: int = 5
    ) -> List[Dict[str, Any]]:
        """
        Fetch last N completed scans for this repository.

        Returns:
            List of scans with vulnerabilities, patches, and outcomes
        """
        query = f"""
        SELECT
            s.scan_id,
            s.timestamp,
            s.commit_sha,
            s.scan_mode,
            s.vulnerabilities_found,
            s.fixes_applied,
            s.findings_summary,
            s.patches_summary,
            s.pr_url,
            s.pr_merged,
            s.llm_model_used,
            o.outcome_type,
            o.rejection_reason,
            o.modifications_made
        FROM `{self.project_id}.{self.dataset_id}.scans` s
        LEFT JOIN `{self.project_id}.{self.dataset_id}.scan_outcomes` o
            ON s.scan_id = o.scan_id
        WHERE s.repo_name = @repo_name
            AND s.status = 'completed'
        ORDER BY s.timestamp DESC
        LIMIT @limit
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("repo_name", "STRING", repo_name),
                bigquery.ScalarQueryParameter("limit", "INT64", limit),
            ]
        )

        try:
            results = self.client.query(query, job_config=job_config).result()

            scans = []
            for row in results:
                scans.append(
                    {
                        "scan_id": row.scan_id,
                        "timestamp": (
                            row.timestamp.isoformat() if row.timestamp else None
                        ),
                        "commit": row.commit_sha[:8] if row.commit_sha else "unknown",
                        "mode": row.scan_mode,
                        "vulnerabilities_found": row.vulnerabilities_found or 0,
                        "fixes_applied": row.fixes_applied or 0,
                        "findings": (
                            json.loads(row.findings_summary)
                            if row.findings_summary
                            else []
                        ),
                        "patches": (
                            json.loads(row.patches_summary)
                            if row.patches_summary
                            else []
                        ),
                        "pr_url": row.pr_url,
                        "pr_merged": row.pr_merged,
                        "model_used": row.llm_model_used,
                        "outcome": row.outcome_type,
                        "rejection_reason": row.rejection_reason,
                        "modifications": row.modifications_made,
                    }
                )

            logger.info(f"Retrieved {len(scans)} past scans for {repo_name}")
            return scans

        except Exception as e:
            logger.error(f"Failed to fetch scan history: {e}")
            return []

    def format_for_llm(self, scans: List[Dict[str, Any]], repo_name: str) -> str:
        """
        Format scan history as markdown for LLM context.

        This is injected into the LLM prompt before analysis so it can:
        - Learn from past successful fixes
        - Avoid repeating rejected approaches
        - Identify recurring issues
        - Match coding style of accepted patches
        """
        if not scans:
            return f"No previous scans found for {repo_name}. This is the first analysis."

        context = f"# Repository Scan History: {repo_name}\n\n"
        context += f"This repository has been scanned **{len(scans)} times** previously. "
        context += "Learn from these past findings and their outcomes:\n\n"

        for idx, scan in enumerate(scans, 1):
            # Header
            scan_date = scan["timestamp"][:10] if scan["timestamp"] else "unknown"
            context += f"## Scan #{idx} ({scan_date})\n"
            context += f"**Commit:** `{scan['commit']}`  \n"
            context += f"**Mode:** {scan['mode']}  \n"
            context += f"**Found:** {scan['vulnerabilities_found']} vulnerabilities  \n"
            context += f"**Fixed:** {scan['fixes_applied']} patches applied  \n\n"

            # Vulnerabilities detail
            if scan["findings"]:
                context += "**Vulnerabilities Found:**\n"
                for finding in scan["findings"]:
                    vuln_type = finding.get("type", "Unknown")
                    file_path = finding.get("file", "unknown")
                    score = finding.get("score", 0.0)
                    severity = finding.get("severity", "UNKNOWN")
                    context += f"- **{vuln_type}** ({severity}, CVSS {score}) in `{file_path}`\n"
                context += "\n"

            # Patches detail
            if scan["patches"]:
                context += "**Patches Applied:**\n"
                for patch in scan["patches"]:
                    patch_type = patch.get("type", "Unknown")
                    file_path = patch.get("file", "unknown")
                    description = patch.get("description", "")
                    context += f"- {patch_type} fix in `{file_path}`\n"
                    if description:
                        context += f"  └─ {description[:100]}\n"
                context += "\n"

            # Outcome (CRITICAL for learning)
            if scan["pr_merged"]:
                context += "✅ **Outcome:** PR merged - fixes were **ACCEPTED**\n"
                context += "   → This approach worked. Consider similar patterns.\n"
            elif scan["outcome"] == "rejected":
                context += "❌ **Outcome:** PR **REJECTED**\n"
                if scan["rejection_reason"]:
                    context += f"   **Reason:** {scan['rejection_reason']}\n"
                    context += "   **⚠️  IMPORTANT:** Avoid suggesting similar fixes.\n"
            elif scan["outcome"] == "modified":
                context += "⚠️  **Outcome:** PR **MODIFIED** before merge\n"
                if scan["modifications"]:
                    context += f"   **Changes made:** {scan['modifications']}\n"
                    context += "   **⚠️  IMPORTANT:** Use this modified approach instead.\n"
            elif scan["pr_url"]:
                context += "⏳ **Outcome:** PR pending review\n"

            context += "\n---\n\n"

        # Strategic guidance based on patterns
        context += self._generate_strategic_guidance(scans)

        return context

    def _generate_strategic_guidance(self, scans: List[Dict[str, Any]]) -> str:
        """
        Analyze scan history to provide strategic guidance.
        """
        guidance = "## 📊 Strategic Guidance for Current Scan\n\n"
        guidance += "Based on repository history:\n\n"

        # Count outcomes
        merged = sum(1 for s in scans if s.get("pr_merged"))
        rejected = sum(1 for s in scans if s.get("outcome") == "rejected")
        modified = sum(1 for s in scans if s.get("outcome") == "modified")

        # Acceptance rate
        total_with_outcome = merged + rejected + modified
        if total_with_outcome > 0:
            acceptance_rate = (merged / total_with_outcome) * 100
            guidance += f"- **Acceptance rate:** {acceptance_rate:.0f}% ({merged}/{total_with_outcome} PRs merged)\n"

            if acceptance_rate >= 80:
                guidance += "  → Team accepts automated patches. Be comprehensive.\n"
            elif acceptance_rate >= 50:
                guidance += "  → Mixed acceptance. Focus on high-confidence fixes.\n"
            else:
                guidance += "  → Low acceptance rate. Be very conservative and explain thoroughly.\n"

        # Recurring issues
        recurring_findings = self._identify_recurring_issues(scans)
        if recurring_findings:
            guidance += "\n**⚠️  RECURRING ISSUES** (found multiple times, not fixed):\n"
            for vuln_type, files in recurring_findings.items():
                guidance += f"- **{vuln_type}** in: {', '.join(files)}\n"
            guidance += "  → These require special attention. Previous fixes may have failed or been incomplete.\n"
            guidance += "  → Consider root cause rather than symptoms.\n"

        # Rejection patterns
        if rejected > 0:
            rejection_reasons = [
                s.get("rejection_reason")
                for s in scans
                if s.get("outcome") == "rejected" and s.get("rejection_reason")
            ]
            if rejection_reasons:
                guidance += f"\n**Common rejection reasons:**\n"
                for reason in set(rejection_reasons):
                    guidance += f"- {reason}\n"

        return guidance

    def _identify_recurring_issues(
        self, scans: List[Dict[str, Any]]
    ) -> Dict[str, List[str]]:
        """
        Find vulnerabilities that appear in multiple scans (not fixed).
        """
        # Track: vulnerability_type:file_path -> scan count
        issue_tracker: Dict[str, set] = {}

        for scan in scans:
            for finding in scan.get("findings", []):
                vuln_type = finding.get("type")
                file_path = finding.get("file")
                if vuln_type and file_path:
                    key = f"{vuln_type}:{file_path}"
                    if key not in issue_tracker:
                        issue_tracker[key] = set()
                    issue_tracker[key].add(scan["scan_id"])

        # Find issues seen in 2+ scans
        recurring = {}
        for key, scan_ids in issue_tracker.items():
            if len(scan_ids) >= 2:
                vuln_type, file_path = key.split(":", 1)
                if vuln_type not in recurring:
                    recurring[vuln_type] = []
                recurring[vuln_type].append(file_path)

        return recurring

    def verify_isolation(self, repo_name: str) -> bool:
        """
        Debug: Verify we're only getting data for this repo.
        Ensures no data leaks between repositories.
        """
        query = f"""
        SELECT DISTINCT s.repo_name
        FROM `{self.project_id}.{self.dataset_id}.scans` s
        LEFT JOIN `{self.project_id}.{self.dataset_id}.vulnerabilities` v
            ON s.scan_id = v.scan_id
        WHERE s.repo_name = @repo_name
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("repo_name", "STRING", repo_name),
            ]
        )

        results = self.client.query(query, job_config=job_config).result()
        repo_names = set(row.repo_name for row in results)

        if len(repo_names) == 0:
            logger.info(f"✅ No data yet for {repo_name}")
            return True
        elif len(repo_names) == 1 and list(repo_names)[0] == repo_name:
            logger.info(f"✅ Isolation verified for {repo_name}")
            return True
        else:
            logger.error(f"❌ Data leak detected! Found repos: {repo_names}")
            return False
