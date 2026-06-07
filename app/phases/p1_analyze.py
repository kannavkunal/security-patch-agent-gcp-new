"""Phase 1: Repository Analysis - Detect languages, dependencies, entry points"""
from .base import Phase
from typing import Dict, Any
import subprocess
import os

class Phase1Analyzer(Phase):
    """Analyze repository structure"""

    def execute(self) -> Dict[str, Any]:
        self.logger.info("Phase 1: Analyzing repository")

        repo_path = self.context.get("repo_path")

        # Detect languages
        languages = self._detect_languages(repo_path)

        # Find dependencies
        dependencies = self._scan_dependencies(repo_path)

        # Find entry points
        entry_points = self._find_entry_points(repo_path, languages)

        result = {
            "languages": languages,
            "dependencies": dependencies,
            "entry_points": entry_points
        }

        self.update_context(result)
        self.logger.info(f"Found languages: {languages}")

        return result

    def _detect_languages(self, repo_path: str) -> list:
        """Detect programming languages"""
        languages = []

        # Simple file extension detection
        for root, dirs, files in os.walk(repo_path):
            for file in files:
                if file.endswith('.py'):
                    if 'python' not in languages:
                        languages.append('python')
                elif file.endswith('.js'):
                    if 'javascript' not in languages:
                        languages.append('javascript')
                elif file.endswith('.java'):
                    if 'java' not in languages:
                        languages.append('java')
                elif file.endswith('.go'):
                    if 'go' not in languages:
                        languages.append('go')

        return languages or ['unknown']

    def _scan_dependencies(self, repo_path: str) -> dict:
        """Scan for dependencies"""
        deps = {}

        # Python
        if os.path.exists(f"{repo_path}/requirements.txt"):
            deps['python'] = self._read_file(f"{repo_path}/requirements.txt")

        # Node.js
        if os.path.exists(f"{repo_path}/package.json"):
            deps['node'] = self._read_file(f"{repo_path}/package.json")

        # Java
        if os.path.exists(f"{repo_path}/pom.xml"):
            deps['java'] = 'pom.xml'

        # Go
        if os.path.exists(f"{repo_path}/go.mod"):
            deps['go'] = self._read_file(f"{repo_path}/go.mod")

        return deps

    def _find_entry_points(self, repo_path: str, languages: list) -> list:
        """Find application entry points"""
        entry_points = []

        for root, dirs, files in os.walk(repo_path):
            for file in files:
                if file in ['main.py', 'app.py', 'server.py', 'main.js', 'app.js', 'Main.java', 'main.go']:
                    entry_points.append(os.path.join(root, file))

        return entry_points

    def _read_file(self, path: str) -> str:
        """Read file content"""
        try:
            with open(path, 'r') as f:
                return f.read()[:500]  # First 500 chars
        except:
            return ""
