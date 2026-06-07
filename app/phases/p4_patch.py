"""Phase 4: Patch Generation - Generate code fixes using Gemini"""
from .base import Phase
from typing import Dict, Any, List
from vertexai.generative_models import GenerativeModel
import os

class Phase4PatchGenerator(Phase):
    def execute(self) -> Dict[str, Any]:
        self.logger.info("Phase 4: Generating patches")

        vulnerabilities = self.context.get("vulnerabilities", [])
        patches = []
        processed_files = set()

        model = GenerativeModel("gemini-2.5-pro")

        # Group vulnerabilities by file and process each file once
        for vuln in vulnerabilities[:10]:  # Limit to top 10 vulns
            file_path = vuln.get('file')
            if file_path and file_path not in processed_files:
                patch = self._generate_patch(vuln, model)
                if patch:
                    patches.append(patch)
                    processed_files.add(file_path)
                    self.logger.info(f"Generated patch for {os.path.basename(file_path)}")

        self.logger.info(f"Generated {len(patches)} patches for {len(processed_files)} files")
        self.update_context({"patches": patches})
        return {"patches": patches}

    def _generate_patch(self, vuln: dict, model) -> dict:
        """Generate patch for a single vulnerability"""
        try:
            file_path = vuln.get('file')

            # Read full file content
            try:
                with open(file_path, 'r') as f:
                    original_content = f.read()
            except Exception as e:
                self.logger.error(f"Cannot read {file_path}: {e}")
                return None

            # Ask LLM to fix the vulnerability in the full file
            prompt = f"""You are a security expert. Fix the {vuln.get('type')} vulnerability in this file.

File: {os.path.basename(file_path)}
Vulnerability at line {vuln.get('line')}: {vuln.get('code_snippet', 'N/A')}

Current file content:
```
{original_content}
```

Provide the COMPLETE fixed file content with the vulnerability patched.
Output ONLY the fixed code, no explanations or markdown formatting."""

            response = model.generate_content(prompt)
            patched_content = response.text.strip()

            # Remove markdown code blocks if present
            if patched_content.startswith('```'):
                lines = patched_content.split('\n')
                patched_content = '\n'.join(lines[1:-1]) if len(lines) > 2 else patched_content

            # Calculate relative path from repo root
            repo_path = self.context.get('repo_path', '')
            relative_path = file_path.replace(repo_path + '/', '') if repo_path else file_path

            return {
                "file_path": relative_path,
                "vulnerability_type": vuln.get('type'),
                "patched_code": patched_content,
                "original_code": original_content
            }
        except Exception as e:
            self.logger.error(f"Patch generation failed: {e}")
            return None
