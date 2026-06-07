"""Kubernetes Job Spawner - Creates ephemeral jobs for security scans"""
import os
from kubernetes import client, config
from kubernetes.client.rest import ApiException
import logging

logger = logging.getLogger(__name__)


class JobSpawner:
    def __init__(self):
        """Initialize Kubernetes client"""
        try:
            # Try loading in-cluster config (when running in K8s)
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes config")
        except config.ConfigException:
            # Fall back to kubeconfig (local development)
            config.load_kube_config()
            logger.info("Loaded kubeconfig for local development")

        self.batch_v1 = client.BatchV1Api()
        self.namespace = os.getenv("K8S_NAMESPACE", "security-patch-agent")
        self.project_id = os.getenv("GCP_PROJECT_ID")
        if not self.project_id:
            raise ValueError("GCP_PROJECT_ID environment variable must be set")
        self.image = os.getenv("SCANNER_IMAGE", f"gcr.io/{self.project_id}/security-patch-agent:latest")

    def create_scan_job(self, scan_id: str, repo_url: str, mode: str, branch: str = "main", pr_number: int = None):
        """
        Create a Kubernetes Job to run a security scan

        Args:
            scan_id: Unique scan identifier
            repo_url: Repository URL to scan
            mode: "patch" or "review"
            branch: Git branch to scan
            pr_number: PR number (for review mode)

        Returns:
            Job name
        """
        job_name = f"scan-{scan_id.split('-')[-1][:8]}"  # Use last 8 chars of UUID

        # Environment variables for the job
        env_vars = [
            client.V1EnvVar(name="SCAN_ID", value=scan_id),
            client.V1EnvVar(name="REPO_URL", value=repo_url),
            client.V1EnvVar(name="SCAN_MODE", value=mode),
            client.V1EnvVar(name="BRANCH", value=branch),
            client.V1EnvVar(name="GCP_PROJECT_ID", value=self.project_id),
        ]

        if pr_number:
            env_vars.append(client.V1EnvVar(name="PR_NUMBER", value=str(pr_number)))

        # Container spec
        container = client.V1Container(
            name="scanner",
            image=self.image,
            image_pull_policy="Always",
            command=["python", "-m", "app.orchestrator"],
            env=env_vars,
            resources=client.V1ResourceRequirements(
                requests={"cpu": "500m", "memory": "1Gi"},
                limits={"cpu": "2", "memory": "4Gi"}
            )
        )

        # Pod template spec
        template = client.V1PodTemplateSpec(
            metadata=client.V1ObjectMeta(
                labels={
                    "app": "security-scanner",
                    "scan-id": scan_id,
                    "mode": mode
                }
            ),
            spec=client.V1PodSpec(
                restart_policy="Never",
                containers=[container],
                service_account_name="security-patch-agent-sa"  # Workload Identity
            )
        )

        # Job spec
        job_spec = client.V1JobSpec(
            template=template,
            backoff_limit=2,  # Retry up to 2 times
            ttl_seconds_after_finished=300,  # Clean up 5 minutes after completion/failure
            active_deadline_seconds=1800  # 30 minute timeout
        )

        # Job
        job = client.V1Job(
            api_version="batch/v1",
            kind="Job",
            metadata=client.V1ObjectMeta(
                name=job_name,
                namespace=self.namespace,
                labels={
                    "app": "security-scanner",
                    "scan-id": scan_id,
                    "mode": mode
                }
            ),
            spec=job_spec
        )

        try:
            # Create the job
            api_response = self.batch_v1.create_namespaced_job(
                namespace=self.namespace,
                body=job
            )
            logger.info(f"Created job {job_name} for scan {scan_id}")
            return job_name

        except ApiException as e:
            logger.error(f"Failed to create job {job_name}: {e}")
            raise

    def get_job_status(self, job_name: str):
        """Get status of a job"""
        try:
            job = self.batch_v1.read_namespaced_job_status(
                name=job_name,
                namespace=self.namespace
            )
            return {
                "active": job.status.active or 0,
                "succeeded": job.status.succeeded or 0,
                "failed": job.status.failed or 0,
                "start_time": job.status.start_time,
                "completion_time": job.status.completion_time
            }
        except ApiException as e:
            logger.error(f"Failed to get job status for {job_name}: {e}")
            return None

    def delete_job(self, job_name: str):
        """Delete a job (cleanup)"""
        try:
            self.batch_v1.delete_namespaced_job(
                name=job_name,
                namespace=self.namespace,
                body=client.V1DeleteOptions(
                    propagation_policy="Foreground"
                )
            )
            logger.info(f"Deleted job {job_name}")
        except ApiException as e:
            logger.error(f"Failed to delete job {job_name}: {e}")
