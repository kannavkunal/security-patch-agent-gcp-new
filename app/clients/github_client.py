"""
GitHub Client - Wrapper around PyGithub for PR creation and commenting
"""
from github import Github, GithubException
from google.cloud import secretmanager
from typing import List, Optional
import logging
import os

logger = logging.getLogger(__name__)


class GitHubClient:
    """Handles all GitHub operations: PR creation, commenting, branch management"""

    def __init__(self, project_id: str = None):
        if project_id is None:
            project_id = os.getenv("GCP_PROJECT_ID")
            if not project_id:
                raise ValueError("GCP_PROJECT_ID environment variable must be set")
        self.project_id = project_id
        self.token = self._get_github_token()
        self.client = Github(self.token)

    def _get_github_token(self) -> str:
        """Retrieve GitHub token from Secret Manager"""
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{self.project_id}/secrets/github-token/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode('UTF-8')

    def create_pr(
        self,
        repo_url: str,
        branch_name: str,
        title: str,
        body: str,
        base: str = "main",
        files_to_update: Optional[dict] = None
    ) -> dict:
        """
        Create a new Pull Request with patches.

        Args:
            repo_url: Full GitHub repo URL
            branch_name: New branch name (e.g., fix/security-patches-2026-06-06)
            title: PR title
            body: PR description
            base: Base branch (default: main)
            files_to_update: {file_path: new_content}

        Returns:
            {"pr_url": str, "pr_number": int}
        """
        try:
            # Extract owner/repo from URL
            parts = repo_url.replace("https://github.com/", "").replace(".git", "").split("/")
            owner, repo_name = parts[0], parts[1]
            repo = self.client.get_repo(f"{owner}/{repo_name}")

            # Create branch from main
            source = repo.get_branch(base)
            repo.create_git_ref(ref=f"refs/heads/{branch_name}", sha=source.commit.sha)

            # Update files
            if files_to_update:
                for file_path, new_content in files_to_update.items():
                    try:
                        contents = repo.get_contents(file_path, ref=branch_name)
                        repo.update_file(
                            path=file_path,
                            message=f"Fix security vulnerability in {file_path}",
                            content=new_content,
                            sha=contents.sha,
                            branch=branch_name
                        )
                    except Exception as e:
                        logger.error(f"Failed to update {file_path}: {e}")

            # Create PR
            pr = repo.create_pull(
                title=title,
                body=body,
                head=branch_name,
                base=base
            )

            logger.info(f"Created PR #{pr.number}: {pr.html_url}")
            return {"pr_url": pr.html_url, "pr_number": pr.number}

        except GithubException as e:
            logger.error(f"GitHub API error: {e}")
            raise

    def comment_on_pr(
        self,
        repo_url: str,
        pr_number: int,
        comment: str,
        inline_comments: Optional[List[dict]] = None
    ) -> None:
        """
        Add comments to an existing PR (review mode).

        Args:
            repo_url: Full GitHub repo URL
            pr_number: PR number
            comment: General comment body
            inline_comments: [{"path": str, "line": int, "body": str}]
        """
        try:
            parts = repo_url.replace("https://github.com/", "").replace(".git", "").split("/")
            owner, repo_name = parts[0], parts[1]
            repo = self.client.get_repo(f"{owner}/{repo_name}")
            pr = repo.get_pull(pr_number)

            # Add general comment
            pr.create_issue_comment(comment)

            # Add inline comments (best-effort, skip if file not in diff)
            inline_added = 0
            if inline_comments:
                commit = pr.get_commits()[pr.commits - 1]  # Latest commit
                for ic in inline_comments:
                    try:
                        pr.create_review_comment(
                            body=ic["body"],
                            commit=commit,
                            path=ic["path"],
                            line=ic["line"]
                        )
                        inline_added += 1
                    except GithubException as e:
                        # Skip if file not in diff (422 error)
                        if e.status == 422:
                            logger.debug(f"Skipped inline comment for {ic['path']} (not in diff)")
                        else:
                            logger.warning(f"Failed to add inline comment: {e}")

            logger.info(f"Added general comment + {inline_added} inline comments to PR #{pr_number}")

        except GithubException as e:
            logger.error(f"GitHub API error: {e}")
            raise

    def request_changes(
        self,
        repo_url: str,
        pr_number: int,
        review_body: str
    ) -> None:
        """Request changes on a PR (if critical vulnerabilities found)"""
        try:
            parts = repo_url.replace("https://github.com/", "").replace(".git", "").split("/")
            owner, repo_name = parts[0], parts[1]
            repo = self.client.get_repo(f"{owner}/{repo_name}")
            pr = repo.get_pull(pr_number)

            pr.create_review(
                body=review_body,
                event="REQUEST_CHANGES"
            )

            logger.info(f"Requested changes on PR #{pr_number}")

        except GithubException as e:
            logger.error(f"GitHub API error: {e}")
            raise
