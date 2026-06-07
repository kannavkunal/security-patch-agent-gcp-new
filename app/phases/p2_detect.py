"""Phase 2: Vulnerability Detection - Run Semgrep, Safety, secret scanning"""
from .base import Phase
from typing import Dict, Any, List
import subprocess
import json
import os

class Phase2Detector(Phase):
    """Detect vulnerabilities using multiple tools"""

    def execute(self) -> Dict[str, Any]:
        self.logger.info("Phase 2: Detecting vulnerabilities")

        repo_path = self.context.get("repo_path")
        languages = self.context.get("languages", [])
        scan_mode = self.context.get("scan_mode")

        vulnerabilities = []

        # Run Semgrep for code analysis
        semgrep_vulns = self._run_semgrep(repo_path)
        vulnerabilities.extend(semgrep_vulns)

        # Run Safety for Python dependencies
        if 'python' in languages:
            safety_vulns = self._run_safety(repo_path)
            vulnerabilities.extend(safety_vulns)

        # Simple pattern matching for common issues
        pattern_vulns = self._pattern_matching(repo_path)
        vulnerabilities.extend(pattern_vulns)

        # REVIEW mode: Only report NEW vulnerabilities (not in base branch)
        if scan_mode == "review":
            vulnerabilities = self._filter_new_vulnerabilities(repo_path, vulnerabilities)

        result = {
            "vulnerabilities": vulnerabilities,
            "vulnerability_count": len(vulnerabilities)
        }

        self.update_context(result)
        self.logger.info(f"Found {len(vulnerabilities)} vulnerabilities")

        return result

    def _run_semgrep(self, repo_path: str) -> List[Dict]:
        """Run Semgrep static analysis"""
        try:
            result = subprocess.run(
                ['semgrep', '--config=auto', '--json', repo_path],
                capture_output=True,
                text=True,
                timeout=120
            )

            if result.returncode == 0:
                data = json.loads(result.stdout)
                return self._parse_semgrep_results(data)
        except Exception as e:
            self.logger.warning(f"Semgrep failed: {e}")

        return []

    def _parse_semgrep_results(self, data: dict) -> List[Dict]:
        """Parse Semgrep JSON output"""
        vulns = []

        for finding in data.get('results', []):
            vulns.append({
                'type': finding.get('check_id', 'Unknown'),
                'file': finding.get('path', ''),
                'line': finding.get('start', {}).get('line', 0),
                'severity': finding.get('extra', {}).get('severity', 'MEDIUM'),
                'description': finding.get('extra', {}).get('message', ''),
                'source': 'semgrep'
            })

        return vulns

    def _run_safety(self, repo_path: str) -> List[Dict]:
        """Run Safety for Python dependencies"""
        req_file = f"{repo_path}/requirements.txt"
        if not os.path.exists(req_file):
            return []

        try:
            result = subprocess.run(
                ['safety', 'check', '--file', req_file, '--json'],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.stdout:
                data = json.loads(result.stdout)
                return self._parse_safety_results(data)
        except Exception as e:
            self.logger.warning(f"Safety failed: {e}")

        return []

    def _parse_safety_results(self, data: list) -> List[Dict]:
        """Parse Safety JSON output"""
        vulns = []

        for vuln in data:
            vulns.append({
                'type': f"Vulnerable dependency: {vuln.get('package', 'unknown')}",
                'file': 'requirements.txt',
                'line': 0,
                'severity': 'HIGH',
                'description': vuln.get('advisory', ''),
                'source': 'safety'
            })

        return vulns

    def _pattern_matching(self, repo_path: str) -> List[Dict]:
        """Simple pattern matching for common vulnerabilities"""
        vulns = []
        patterns = {
            'SQL Injection': [r"execute\(.*\+", r"query.*\+.*user", r"SELECT.*\+"],
            'Command Injection': [r"os\.system\(", r"exec\(", r"subprocess.*shell=True"],
            'Hardcoded Credentials': [r"password\s*=\s*['\"]", r"api_key\s*=\s*['\"]"],
        }

        for root, dirs, files in os.walk(repo_path):
            for file in files:
                if file.endswith(('.py', '.js', '.java', '.go')):
                    filepath = os.path.join(root, file)
                    vulns.extend(self._scan_file_patterns(filepath, patterns))

        return vulns

    def _scan_file_patterns(self, filepath: str, patterns: dict) -> List[Dict]:
        """Scan a file for vulnerability patterns"""
        import re
        vulns = []

        try:
            with open(filepath, 'r') as f:
                lines = f.readlines()

            for line_num, line in enumerate(lines, 1):
                for vuln_type, pattern_list in patterns.items():
                    for pattern in pattern_list:
                        if re.search(pattern, line):
                            vulns.append({
                                'type': vuln_type,
                                'file': filepath,
                                'line': line_num,
                                'severity': 'HIGH',
                                'description': f"Potential {vuln_type} detected",
                                'code_snippet': line.strip(),
                                'source': 'pattern_matching'
                            })
        except Exception as e:
            self.logger.debug(f"Could not scan {filepath}: {e}")

        return vulns

    def _filter_new_vulnerabilities(self, repo_path: str, current_vulns: List[Dict]) -> List[Dict]:
        """Filter to only NEW vulnerabilities introduced by PR (REVIEW mode)"""
        try:
            # Get base branch (usually main or master)
            base_branch = self._get_base_branch(repo_path)

            # Save current branch
            current_branch = subprocess.run(
                ['git', '-C', repo_path, 'rev-parse', '--abbrev-ref', 'HEAD'],
                capture_output=True,
                text=True,
                timeout=5
            ).stdout.strip()

            self.logger.info(f"Comparing {current_branch} against base branch {base_branch}")

            # Checkout base branch
            subprocess.run(
                ['git', '-C', repo_path, 'checkout', base_branch],
                capture_output=True,
                timeout=10
            )

            # Scan base branch
            base_semgrep = self._run_semgrep(repo_path)
            base_pattern = self._pattern_matching(repo_path)
            base_vulns = base_semgrep + base_pattern

            # Return to PR branch
            subprocess.run(
                ['git', '-C', repo_path, 'checkout', current_branch],
                capture_output=True,
                timeout=10
            )

            # Compare: Find vulnerabilities NOT in base
            new_vulns = []
            for vuln in current_vulns:
                if not self._vulnerability_exists(vuln, base_vulns):
                    new_vulns.append(vuln)

            self.logger.info(f"Filtered: {len(current_vulns)} total → {len(new_vulns)} new vulnerabilities")
            return new_vulns

        except Exception as e:
            self.logger.warning(f"Could not filter vulnerabilities: {e}. Returning all.")
            return current_vulns

    def _get_base_branch(self, repo_path: str) -> str:
        """Get the base branch (main or master)"""
        # Check if main exists
        result = subprocess.run(
            ['git', '-C', repo_path, 'rev-parse', '--verify', 'origin/main'],
            capture_output=True,
            timeout=5
        )
        if result.returncode == 0:
            return 'main'

        # Fallback to master
        return 'master'

    def _vulnerability_exists(self, vuln: Dict, base_vulns: List[Dict]) -> bool:
        """Check if vulnerability exists in base branch"""
        # Normalize file path (remove repo_path prefix)
        vuln_file = vuln.get('file', '').split('/')[-1]

        for base_vuln in base_vulns:
            base_file = base_vuln.get('file', '').split('/')[-1]

            # Match by: file name, line number, and type
            if (vuln_file == base_file and
                vuln.get('line') == base_vuln.get('line') and
                vuln.get('type') == base_vuln.get('type')):
                return True

        return False
