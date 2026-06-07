"""8-Phase Orchestrator - Coordinates scan execution"""
from app.phases.p1_analyze import Phase1Analyzer
from app.phases.p2_detect import Phase2Detector
from app.phases.p3_plan import Phase3Planner
from app.phases.p4_patch import Phase4PatchGenerator
from app.phases.p6_github import Phase6GitHub
from app.phases.p7_log import Phase7Logger
from app.phases.p8_evidence import Phase8Evidence
import logging
import uuid
import os
import subprocess
import tempfile
import shutil
from google.cloud import secretmanager

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class Orchestrator:
    """Coordinate 7-phase scan execution"""

    def __init__(self, context: dict):
        self.context = context
        self.context["scan_id"] = f"scan-{uuid.uuid4().hex[:8]}"

        # Extract repo_name from repo_url for logging
        repo_url = self.context.get("repo_url", "")
        if repo_url:
            # Extract owner/repo from https://github.com/owner/repo or https://github.com/owner/repo.git
            repo_name = repo_url.replace("https://github.com/", "").replace(".git", "").strip("/")
            self.context["repo_name"] = repo_name

    def _clone_repository(self) -> str:
        """Clone repository and return local path"""
        repo_url = self.context.get("repo_url")
        branch = self.context.get("branch", "main")

        # Get GitHub token from Secret Manager
        project_id = os.getenv("GCP_PROJECT_ID")
        if not project_id:
            raise ValueError("GCP_PROJECT_ID environment variable must be set")
        client = secretmanager.SecretManagerServiceClient()
        secret_name = f"projects/{project_id}/secrets/github-token/versions/latest"
        response = client.access_secret_version(request={"name": secret_name})
        token = response.payload.data.decode("UTF-8").strip()

        # Create temp directory
        temp_dir = tempfile.mkdtemp(prefix="scan-")

        # Clone with token
        auth_url = repo_url.replace("https://", f"https://{token}@")
        logger.info(f"Cloning {repo_url} to {temp_dir}")

        # Set environment variables to disable Git credential prompting
        env = os.environ.copy()
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "echo"  # Disable password prompting

        result = subprocess.run(
            ["git", "clone", "--depth", "1", "--branch", branch, auth_url, temp_dir],
            capture_output=True,
            text=True,
            timeout=300,
            env=env
        )

        if result.returncode != 0:
            raise Exception(f"Git clone failed: {result.stderr}")

        logger.info(f"Repository cloned to {temp_dir}")
        return temp_dir

    def run(self) -> dict:
        """Execute all phases"""
        logger.info(f"Starting scan {self.context['scan_id']}")

        try:
            # Phase 0: Clone repository
            repo_path = self._clone_repository()
            self.context["repo_path"] = repo_path

            # Phase 1: Analyze
            Phase1Analyzer(self.context).execute()

            # Phase 2: Detect
            Phase2Detector(self.context).execute()

            # Phase 3: Plan
            Phase3Planner(self.context).execute()

            # Phase 4: Generate patches
            Phase4PatchGenerator(self.context).execute()

            # Phase 5: Verify (stub - skip for now)

            # Phase 6: GitHub
            Phase6GitHub(self.context).execute()

            # Phase 8: Generate Evidence (before logging to BQ)
            Phase8Evidence(self.context).execute()

            # Phase 7: Log to BigQuery (includes evidence GCS link)
            Phase7Logger(self.context).execute()

            logger.info(f"Scan {self.context['scan_id']} completed")
            return {"status": "success", "scan_id": self.context["scan_id"]}

        except Exception as e:
            logger.error(f"Scan failed: {e}")
            return {"status": "failed", "error": str(e)}

        finally:
            # Cleanup: remove cloned repository
            repo_path = self.context.get("repo_path")
            if repo_path and os.path.exists(repo_path):
                logger.info(f"Cleaning up {repo_path}")
                shutil.rmtree(repo_path, ignore_errors=True)


if __name__ == "__main__":
    """Entry point when run as K8s Job"""
    # Read configuration from environment variables
    context = {
        "scan_id": os.getenv("SCAN_ID"),
        "repo_url": os.getenv("REPO_URL"),
        "scan_mode": os.getenv("SCAN_MODE", "patch"),
        "branch": os.getenv("BRANCH", "main"),
    }

    # Add PR number if provided (review mode)
    pr_number = os.getenv("PR_NUMBER")
    if pr_number:
        context["pr_number"] = int(pr_number)

    # Validate required fields
    if not context["scan_id"] or not context["repo_url"]:
        logger.error("Missing required environment variables: SCAN_ID, REPO_URL")
        exit(1)

    logger.info(f"Starting orchestrator with context: {context}")

    # Run the scan
    orchestrator = Orchestrator(context)
    result = orchestrator.run()

    # Exit with appropriate code
    exit(0 if result["status"] == "success" else 1)
