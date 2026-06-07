"""Phase 6: GitHub Integration - Dual mode: CREATE PR or COMMENT on existing PR"""
from .base import Phase
from typing import Dict, Any
from app.clients.github_client import GitHubClient
from datetime import datetime
import json

class Phase6GitHub(Phase):
    """Handle GitHub operations based on scan mode"""

    def execute(self) -> Dict[str, Any]:
        mode = self.context.get("scan_mode")

        if mode == "patch":
            return self._create_pr()
        elif mode == "review":
            return self._add_pr_comments()
        else:
            raise ValueError(f"Unknown mode: {mode}")

    def _create_pr(self) -> Dict[str, Any]:
        """Create NEW PR with patches (patch mode)"""
        self.logger.info("Creating new PR with patches")

        repo_url = self.context.get("repo_url")
        scan_id = self.context.get("scan_id")
        patches = self.context.get("patches", [])
        vulnerabilities = self.context.get("vulnerabilities", [])

        # Create branch name
        branch_name = f"fix/security-patches-{datetime.now().strftime('%Y%m%d-%H%M%S')}"

        # Prepare files to update
        files_to_update = {}
        for patch in patches:
            files_to_update[patch['file_path']] = patch['patched_code']

        # Format PR body
        pr_body = self._format_pr_body(vulnerabilities, patches, scan_id)

        # Create PR
        client = GitHubClient()
        result = client.create_pr(
            repo_url=repo_url,
            branch_name=branch_name,
            title=f"🔒 Security Patches (scan-{scan_id})",
            body=pr_body,
            files_to_update=files_to_update
        )

        self.logger.info(f"Created PR: {result['pr_url']}")
        self.update_context(result)

        return result

    def _add_pr_comments(self) -> Dict[str, Any]:
        """Add comments to EXISTING PR (review mode)"""
        self.logger.info("Adding comments to existing PR")

        repo_url = self.context.get("repo_url")
        pr_number = self.context.get("pr_number")
        vulnerabilities = self.context.get("vulnerabilities", [])

        # Format general comment (always add this)
        general_comment = self._format_review_comment(vulnerabilities)

        # Only prepare inline comments if there are vulnerabilities
        inline_comments = []
        if len(vulnerabilities) > 0:
            for vuln in vulnerabilities[:5]:  # Limit to 5 inline comments
                inline_comments.append({
                    "path": vuln.get('file', '').replace(self.context.get('repo_path', ''), '').lstrip('/'),
                    "line": vuln.get('line', 1),
                    "body": f"⚠️ **{vuln.get('type')}**\n\n{vuln.get('description', '')}"
                })

        # Add comments (inline comments are best-effort in github_client)
        client = GitHubClient()
        client.comment_on_pr(repo_url, pr_number, general_comment, inline_comments if inline_comments else None)

        # Request changes if critical vulns found
        critical_count = sum(1 for v in vulnerabilities if v.get('severity') == 'CRITICAL')
        if critical_count > 0:
            client.request_changes(repo_url, pr_number, f"{critical_count} critical vulnerabilities detected. Please review.")

        result = {"pr_number": pr_number, "comments_added": 1 + len(inline_comments)}
        self.update_context(result)

        return result

    def _format_pr_body(self, vulns: list, patches: list, scan_id: str) -> str:
        """Generate PR body using LLM for consistent format"""
        try:
            from vertexai.generative_models import GenerativeModel
            model = GenerativeModel("gemini-2.5-pro")

            # Prepare vulnerability summary
            vuln_summary = []
            for v in vulns[:10]:
                vuln_summary.append({
                    "type": v.get('type'),
                    "file": v.get('file', '').split('/')[-1],  # basename only
                    "line": v.get('line'),
                    "severity": v.get('severity')
                })

            prompt = f"""You are a security engineer. Create a pull request description for automated security patches.

Scan ID: {scan_id}
Vulnerabilities Found: {len(vulns)}
Patches Generated: {len(patches)}

Vulnerabilities:
{json.dumps(vuln_summary, indent=2)}

You MUST respond with ONLY a valid JSON object in this exact format:
{{
  "title": "Brief PR title (under 60 chars)",
  "summary": "2-3 sentence overview of what vulnerabilities were found and fixed",
  "risk_assessment": "Brief statement about the security risk if not patched",
  "changes_made": "List of files modified and what was fixed (as markdown bullet list string)",
  "testing_notes": "How to verify the patches don't break functionality"
}}

Do not include markdown code blocks, explanations, or extra text. Output ONLY the JSON object."""

            response = model.generate_content(prompt)
            result_text = response.text.strip()

            # Remove markdown if present
            if result_text.startswith('```'):
                result_text = result_text.split('```')[1]
                if result_text.startswith('json'):
                    result_text = result_text[4:]
                result_text = result_text.strip()

            content = json.loads(result_text)

            return f"""## 🔒 Automated Security Fixes — {content['title']}

**Mode:** PATCH (automated vulnerability remediation)
**Scan ID:** `{scan_id}`
**Vulnerabilities Fixed:** {len(patches)}

### Summary

{content['summary']}

### Risk Assessment

{content['risk_assessment']}

### Changes Made

{content['changes_made']}

### Testing Recommendations

{content['testing_notes']}

### Evidence

Detailed security analysis (CVSS scores, attack patterns, exploitation scenarios) will be available in GCS.
Check PR comments below for the evidence link.

---

🤖 **Automated security patch** • Generated by [Security Patch Agent](https://github.com/kannavkunal/security-patch-agent)
"""

        except Exception as e:
            self.logger.warning(f"LLM PR body generation failed: {e}, using template")
            # Fallback to template
            return f"""## 🔒 Automated Security Fixes

**Mode:** PATCH (automated vulnerability remediation)
**Scan ID:** `{scan_id}`
**Vulnerabilities Fixed:** {len(patches)}

### Vulnerabilities Addressed

{chr(10).join([f"- **{v.get('type')}** in `{v.get('file')}:{v.get('line')}` ({v.get('severity')})" for v in vulns[:10]])}

### Changes Made

{chr(10).join([f"- Fixed {p.get('vulnerability_type')} in `{p.get('file_path')}`" for p in patches])}

### Evidence

Detailed security analysis will be available in GCS. Check PR comments below for the evidence link.

---
🤖 **Automated security patch** • Generated by [Security Patch Agent](https://github.com/kannavkunal/security-patch-agent)
"""

    def _format_review_comment(self, vulns: list) -> str:
        """Generate review comment using LLM for consistent format"""
        critical = sum(1 for v in vulns if v.get('severity') == 'CRITICAL')
        high = sum(1 for v in vulns if v.get('severity') == 'HIGH')
        medium = sum(1 for v in vulns if v.get('severity') in ['MEDIUM', 'WARNING'])

        # If 0 vulnerabilities found
        if len(vulns) == 0:
            return f"""## ✅ Automated Security Review — No New Issues

**Scan Mode:** REVIEW (analyzing PR changes only)

This PR does not introduce any new security vulnerabilities.

### Analysis
- 🔴 **Critical:** 0
- 🟠 **High:** 0
- 🟡 **Medium/Low:** 0
- **Total New Issues:** 0

✅ **This PR is safe to merge** from a security perspective.

---
🤖 Automated security scan • Only reports NEW vulnerabilities introduced by this PR
"""

        try:
            from vertexai.generative_models import GenerativeModel
            model = GenerativeModel("gemini-2.5-pro")

            # Prepare vulnerability summary
            vuln_summary = []
            for v in vulns[:5]:  # Top 5 for context
                vuln_summary.append({
                    "type": v.get('type'),
                    "severity": v.get('severity'),
                    "file": v.get('file', '').split('/')[-1]
                })

            prompt = f"""You are a security reviewer. Create a PR comment for security scan results.

Total NEW Vulnerabilities Introduced: {len(vulns)}
Critical: {critical}
High: {high}
Medium: {medium}

Top Vulnerabilities:
{json.dumps(vuln_summary, indent=2)}

You MUST respond with ONLY a valid JSON object in this exact format:
{{
  "headline": "Clear headline about the NEW security issues found (1 sentence)",
  "impact_summary": "What's the security impact if these aren't fixed (2-3 sentences)",
  "priority_action": "What should be done before merging (1 sentence)",
  "note": "Any additional context or recommendations"
}}

Do not include markdown code blocks, explanations, or extra text. Output ONLY the JSON object."""

            response = model.generate_content(prompt)
            result_text = response.text.strip()

            # Remove markdown if present
            if result_text.startswith('```'):
                result_text = result_text.split('```')[1]
                if result_text.startswith('json'):
                    result_text = result_text[4:]
                result_text = result_text.strip()

            content = json.loads(result_text)

            return f"""## ⚠️ Automated Security Review — Issues Found

**Scan Mode:** REVIEW (analyzing PR changes only)

{content['headline']}

### New Vulnerabilities Introduced

- 🔴 **Critical:** {critical}
- 🟠 **High:** {high}
- 🟡 **Medium/Low:** {len(vulns) - critical - high}
- **Total New Issues:** {len(vulns)}

### Impact

{content['impact_summary']}

### Recommended Action

{content['priority_action']}

### Additional Notes

{content['note']}

---
🤖 Automated security scan • Only reports NEW vulnerabilities introduced by this PR
"""

        except Exception as e:
            self.logger.warning(f"LLM review comment generation failed: {e}, using template")
            # Fallback
            return f"""## ⚠️ Automated Security Review — Issues Found

**Scan Mode:** REVIEW (analyzing PR changes only)

Found **{len(vulns)} NEW vulnerabilities** introduced by this PR:

- 🔴 **Critical:** {critical}
- 🟠 **High:** {high}
- 🟡 **Medium/Low:** {len(vulns) - critical - high}

### What This Means
These vulnerabilities were NOT present in the base branch.
This PR introduces new security issues that should be fixed before merging.

---
🤖 Automated security scan • Only reports NEW vulnerabilities introduced by this PR
"""
