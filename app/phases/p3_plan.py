"""Phase 3: Planning with Context - Use RepoMemory + Gemini to plan remediation"""
from .base import Phase
from typing import Dict, Any
from app.context.repo_memory import RepoMemory
from vertexai.generative_models import GenerativeModel
import os

class Phase3Planner(Phase):
    """Plan remediation with LLM context memory - KEY INNOVATION"""

    def execute(self) -> Dict[str, Any]:
        self.logger.info("Phase 3: Planning remediation with LLM context")

        repo_name = self.context.get("repo_name")
        vulnerabilities = self.context.get("vulnerabilities", [])

        # Get repository history (last 5 scans)
        project_id = os.getenv("GCP_PROJECT_ID")
        if not project_id:
            raise ValueError("GCP_PROJECT_ID environment variable must be set")
        memory = RepoMemory(project_id=project_id)
        past_scans = memory.get_recent_scans(repo_name, limit=5)
        context_text = memory.format_for_llm(past_scans, repo_name)

        # Generate remediation plan with context
        plan = self._generate_plan(vulnerabilities, context_text)

        result = {"remediation_plan": plan, "llm_context_used": len(past_scans) > 0}
        self.update_context(result)

        return result

    def _generate_plan(self, vulns: list, context: str) -> dict:
        """Generate remediation plan using Gemini with structured JSON output"""
        model = GenerativeModel("gemini-2.5-pro")

        prompt = f"""
{context}

# Current Vulnerabilities Found

{len(vulns)} vulnerabilities detected:

{self._format_vulns(vulns)}

You MUST respond with ONLY a valid JSON object in this exact format:
{{
  "summary": "brief analysis of the vulnerabilities and attack surface",
  "priorities": ["V-001: Critical SQL injection in app.py:15", "V-002: High severity XSS in routes.py:42"],
  "recommendations": {{
    "V-001": "Use parameterized queries with prepared statements",
    "V-002": "Sanitize all user input before rendering"
  }}
}}

Do not include any explanations, markdown formatting, or additional text. Output ONLY the JSON object.
"""

        try:
            response = model.generate_content(prompt)
            import json

            # Remove markdown code blocks if present
            result_text = response.text.strip()
            if result_text.startswith('```'):
                result_text = result_text.split('```')[1]
                if result_text.startswith('json'):
                    result_text = result_text[4:]
                result_text = result_text.strip()

            return json.loads(result_text)
        except Exception as e:
            self.logger.warning(f"Plan generation failed: {e}")
            return {"summary": "Plan generation in progress", "priorities": [], "recommendations": {}}

    def _format_vulns(self, vulns: list) -> str:
        """Format vulnerabilities for prompt"""
        return "\n".join([f"- {v.get('type')} in {v.get('file')}:{v.get('line')}" for v in vulns[:10]])
