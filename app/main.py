from fastapi import FastAPI, HTTPException, Header, Depends, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel, field_validator, Field
import vertexai
from vertexai.generative_models import GenerativeModel
import os
import json
import re
import logging
from typing import Optional, List, ClassVar
import hashlib
import hmac
from google.cloud import pubsub_v1
from google.cloud import secretmanager
from google.cloud import bigquery
import uuid
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Security Patch Agent", version="1.0.0")

# Add CORS middleware to allow browser requests
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins (browser file:// and http://)
    allow_credentials=True,
    allow_methods=["*"],  # Allow all methods (GET, POST, etc.)
    allow_headers=["*"],  # Allow all headers (including X-API-Key)
)

# Mount static files directory for UI
static_dir = os.path.join(os.path.dirname(__file__), "static")
if os.path.exists(static_dir):
    app.mount("/static", StaticFiles(directory=static_dir), name="static")

# API Key Authentication
API_KEY_NAME = "X-API-Key"
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)

# Load API keys from environment (comma-separated)
VALID_API_KEYS = os.getenv("API_KEYS", "").split(",") if os.getenv("API_KEYS") else []

async def verify_api_key(api_key: str = Depends(api_key_header)):
    """Verify API key from header"""
    # Skip validation if no API keys configured (for testing)
    if not VALID_API_KEYS or VALID_API_KEYS == ['']:
        return None

    if not api_key:
        raise HTTPException(
            status_code=401,
            detail="Missing API Key",
            headers={"WWW-Authenticate": "ApiKey"},
        )

    # Constant-time comparison to prevent timing attacks
    is_valid = any(
        hmac.compare_digest(api_key, valid_key)
        for valid_key in VALID_API_KEYS
        if valid_key
    )

    if not is_valid:
        raise HTTPException(
            status_code=401,
            detail="Invalid API Key"
        )

    return api_key

# Configuration
PROJECT_ID = os.getenv("GCP_PROJECT_ID")
if not PROJECT_ID:
    raise ValueError("GCP_PROJECT_ID environment variable must be set")
LOCATION = os.getenv("GCP_LOCATION", "us-central1")
PUBSUB_TOPIC = os.getenv("PUBSUB_TOPIC", "security-scan-events")
IS_TESTING = os.getenv("TESTING", "false").lower() == "true"

# Lazy-initialized clients (only created when needed, not at import time)
_publisher = None
_topic_path = None
_secret_client = None
_model = None
_bq_client = None


def get_model():
    """Lazy-initialize Vertex AI model"""
    global _model
    if _model is None and not IS_TESTING:
        vertexai.init(project=PROJECT_ID, location=LOCATION)
        _model = GenerativeModel("gemini-2.5-pro")
    return _model


def get_publisher():
    """Lazy-initialize Pub/Sub publisher"""
    global _publisher, _topic_path
    if _publisher is None and not IS_TESTING:
        _publisher = pubsub_v1.PublisherClient()
        _topic_path = _publisher.topic_path(PROJECT_ID, PUBSUB_TOPIC)
    return _publisher, _topic_path


def get_secret_client():
    """Lazy-initialize Secret Manager client"""
    global _secret_client
    if _secret_client is None and not IS_TESTING:
        _secret_client = secretmanager.SecretManagerServiceClient()
    return _secret_client


def get_bq_client():
    """Lazy-initialize BigQuery client"""
    global _bq_client
    if _bq_client is None and not IS_TESTING:
        _bq_client = bigquery.Client(project=PROJECT_ID)
    return _bq_client


def get_webhook_secret():
    """Retrieve GitHub webhook secret from Secret Manager"""
    try:
        client = get_secret_client()
        if client is None:
            return None
        secret_name = f"projects/{PROJECT_ID}/secrets/github-webhook-secret/versions/latest"
        response = client.access_secret_version(request={"name": secret_name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        print(f"Warning: Could not load webhook secret: {e}")
        return None


def publish_scan_event(repo_url: str, mode: str, branch: str = "main", pr_number: Optional[int] = None):
    """Publish scan event to Pub/Sub"""
    scan_id = f"scan-{uuid.uuid4()}"

    message_data = {
        "scan_id": scan_id,
        "repo_url": repo_url,
        "mode": mode,
        "branch": branch,
        "trigger_type": "webhook" if pr_number else "api"
    }

    if pr_number:
        message_data["pr_number"] = pr_number

    publisher, topic_path = get_publisher()
    if publisher is None:
        # In test mode, just return scan_id without publishing
        return scan_id

    message_bytes = json.dumps(message_data).encode("utf-8")
    future = publisher.publish(topic_path, message_bytes)
    future.result()  # Wait for publish to complete

    return scan_id


class CodeAnalysisRequest(BaseModel):
    code: str
    language: Optional[str] = "auto-detect"
    context: Optional[str] = None


class CodeAnalysisResponse(BaseModel):
    is_vulnerable: bool
    vulnerabilities: list[dict]
    severity: str
    recommendations: list[str]
    summary: str


class ScanRequest(BaseModel):
    repo_url: str = Field(..., min_length=20, max_length=500, description="GitHub repository URL")
    mode: str = Field("patch", pattern="^(patch|review)$", description="Scan mode: patch or review")
    branch: str = Field("main", min_length=1, max_length=255, description="Git branch name")

    # Whitelist of allowed repositories
    ALLOWED_REPOS: ClassVar[List[str]] = [
        "https://github.com/kannavkunal/vulnerable-python-api",
        "https://github.com/kannavkunal/vulnerable-java-app",
        "https://github.com/kannavkunal/vulnerable-node-service",
        "https://github.com/kannavkunal/vulnerable-go-microservice"
    ]

    @field_validator('repo_url')
    @classmethod
    def validate_repo_url(cls, v):
        """Validate repository URL format and whitelist"""
        # Normalize URL (remove trailing slash)
        v = v.rstrip('/')

        # Must be valid GitHub HTTPS URL
        if not re.match(r'^https://github\.com/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$', v):
            raise ValueError('Repository URL must be a valid GitHub HTTPS URL format: https://github.com/owner/repo')

        # Must be in whitelist
        if v not in cls.ALLOWED_REPOS:
            raise ValueError(
                f'Repository not in whitelist. Allowed repos: {", ".join(cls.ALLOWED_REPOS)}'
            )

        return v

    @field_validator('branch')
    @classmethod
    def validate_branch(cls, v):
        """Validate branch name to prevent injection"""
        # Prevent path traversal
        if '../' in v or '..' in v or v.startswith('/') or v.startswith('.'):
            raise ValueError('Invalid branch name: path traversal detected')

        # Must match git branch naming conventions
        if not re.match(r'^[a-zA-Z0-9/_.-]+$', v):
            raise ValueError('Branch name contains invalid characters')

        return v


class ScanResponse(BaseModel):
    status: str
    scan_id: str
    message: str


class ScanRecord(BaseModel):
    scan_id: str
    timestamp: str
    repo_name: str
    repo_owner: Optional[str] = None
    branch: str
    scan_mode: str
    status: str
    trigger_type: Optional[str] = None
    vulnerabilities_found: Optional[int] = None
    fixes_applied: Optional[int] = None
    pr_url: Optional[str] = None
    pr_number: Optional[int] = None
    evidence_path: Optional[str] = None
    llm_model_used: Optional[str] = None


class ScansListResponse(BaseModel):
    total: int
    scans: List[ScanRecord]
    filters_applied: dict


@app.get("/")
async def root():
    """Serve the dashboard UI"""
    static_dir = os.path.join(os.path.dirname(__file__), "static")
    index_path = os.path.join(static_dir, "index.html")
    if os.path.exists(index_path):
        return FileResponse(index_path)
    else:
        # Fallback to JSON if UI not available
        return {
            "service": "Security Patch Agent",
            "version": "1.0.0",
            "status": "running",
            "ai_backend": "Google Gemini",
            "project": PROJECT_ID
        }

@app.get("/api")
async def api_info():
    """API information endpoint"""
    return {
        "service": "Security Patch Agent",
        "version": "1.0.0",
        "status": "running",
        "ai_backend": "Google Gemini",
        "project": PROJECT_ID
    }


@app.get("/health")
async def health_check():
    return {"status": "healthy", "model": "gemini-2.5-pro"}


@app.get("/test")
async def test_auth(api_key: str = Depends(verify_api_key)):
    """Test endpoint that requires valid API key"""
    return {
        "status": "authenticated",
        "message": "API key is valid",
        "model": "gemini-2.5-pro"
    }


@app.get("/repositories")
async def get_allowed_repositories():
    """
    Get list of allowed repositories that can be scanned
    No authentication required - this is public information
    """
    return {
        "repositories": ScanRequest.ALLOWED_REPOS,
        "count": len(ScanRequest.ALLOWED_REPOS)
    }


@app.post("/scan", response_model=ScanResponse)
async def trigger_scan(
    request: ScanRequest,
    api_key: str = Depends(verify_api_key)
):
    """
    Trigger a security scan for a repository
    Mode: "patch" (create PR with fixes) or "review" (comment on existing PR)

    Allowed repositories:
    - https://github.com/kannavkunal/vulnerable-python-api
    - https://github.com/kannavkunal/vulnerable-java-app
    - https://github.com/kannavkunal/vulnerable-node-service
    - https://github.com/kannavkunal/vulnerable-go-microservice
    """
    try:
        # Pydantic validation already handled mode, repo_url, and branch
        # Publish to Pub/Sub for async processing
        scan_id = publish_scan_event(
            repo_url=request.repo_url,
            mode=request.mode,
            branch=request.branch
        )

        return ScanResponse(
            status="queued",
            scan_id=scan_id,
            message=f"Scan queued successfully. Mode: {request.mode}, Repository: {request.repo_url}"
        )

    except HTTPException:
        # Re-raise HTTP exceptions (validation errors)
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to queue scan: {str(e)}")


@app.post("/webhook/github")
async def github_webhook(request: Request):
    """Handle GitHub webhook events (PR opened/updated)"""
    payload = await request.body()
    event_type = request.headers.get("X-GitHub-Event")
    signature = request.headers.get("X-Hub-Signature-256", "")

    # Verify webhook signature
    webhook_secret = get_webhook_secret()
    if webhook_secret:
        expected_signature = "sha256=" + hmac.new(
            webhook_secret.encode(),
            payload,
            hashlib.sha256
        ).hexdigest()

        if not hmac.compare_digest(signature, expected_signature):
            raise HTTPException(status_code=401, detail="Invalid webhook signature")

    # Parse payload
    data = json.loads(payload)

    # Handle pull request events
    if event_type == "pull_request":
        action = data.get("action")

        if action in ["opened", "synchronize"]:
            # Extract PR details
            pr = data.get("pull_request", {})
            repo = data.get("repository", {})

            # Get HTTPS URL instead of clone_url (which might be git://)
            repo_url = repo.get("html_url", "").rstrip('/')
            pr_number = pr.get("number")
            branch = pr.get("head", {}).get("ref", "main")

            # Validate repository is in whitelist (use same whitelist as ScanRequest)
            if repo_url not in ScanRequest.ALLOWED_REPOS:
                logger.warning(f"Webhook received for non-whitelisted repo: {repo_url}")
                raise HTTPException(
                    status_code=403,
                    detail=f"Repository not in whitelist: {repo_url}"
                )

            # Validate branch name
            if '../' in branch or branch.startswith('/') or branch.startswith('.'):
                logger.warning(f"Invalid branch name in webhook: {branch}")
                raise HTTPException(
                    status_code=400,
                    detail="Invalid branch name"
                )

            # Validate PR number
            if not pr_number or not isinstance(pr_number, int) or pr_number <= 0:
                raise HTTPException(
                    status_code=400,
                    detail="Invalid or missing PR number"
                )

            logger.info(f"Webhook: Queueing review scan for {repo_url} PR#{pr_number}")

            # Publish to Pub/Sub for review mode scan
            scan_id = publish_scan_event(
                repo_url=repo_url,
                mode="review",
                branch=branch,
                pr_number=pr_number
            )

            return {
                "status": "queued",
                "mode": "review",
                "scan_id": scan_id,
                "pr_number": pr_number,
                "repo": repo_url
            }

    return {"status": "processed", "message": "Event ignored (not a PR open/sync)"}


@app.post("/analyze", response_model=CodeAnalysisResponse)
async def analyze_code(
    request: CodeAnalysisRequest,
    api_key: str = Depends(verify_api_key)
):
    """
    Analyze code for security vulnerabilities using Google Gemini AI
    """
    try:
        # Construct the prompt for Gemini
        prompt = f"""You are a security expert analyzing code for vulnerabilities.
Analyze the following code and identify any security vulnerabilities.

Language: {request.language}
{f"Context: {request.context}" if request.context else ""}

Code:
```
{request.code}
```

Please provide:
1. Whether the code contains vulnerabilities (yes/no)
2. List of specific vulnerabilities found with details
3. Overall severity (Critical, High, Medium, Low, or None)
4. Specific recommendations to fix each vulnerability

Format your response as JSON with the following structure:
{{
  "is_vulnerable": true/false,
  "vulnerabilities": [
    {{
      "type": "vulnerability type",
      "description": "detailed description",
      "line_numbers": "affected lines",
      "severity": "Critical/High/Medium/Low"
    }}
  ],
  "severity": "overall severity level",
  "recommendations": ["specific fix recommendations"],
  "summary": "brief summary of findings"
}}"""

        # Call Gemini API
        model = get_model()
        response = model.generate_content(prompt)
        response_text = response.text

        # Extract JSON from response (Gemini might wrap it in markdown)
        # Try to extract JSON from markdown code blocks
        json_match = re.search(r'```json\n(.*?)\n```', response_text, re.DOTALL)
        if json_match:
            response_text = json_match.group(1)
        else:
            # Try to find JSON object
            json_match = re.search(r'\{.*\}', response_text, re.DOTALL)
            if json_match:
                response_text = json_match.group(0)

        analysis_result = json.loads(response_text)

        return CodeAnalysisResponse(**analysis_result)

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Analysis failed: {str(e)}")


@app.get("/scans", response_model=ScansListResponse)
async def list_scans(
    api_key: str = Depends(verify_api_key),
    repo_name: Optional[str] = Query(None, description="Filter by repo (e.g., 'kannavkunal/vulnerable-python-api')"),
    scan_mode: Optional[str] = Query(None, pattern="^(patch|review)$", description="Filter by mode: 'patch' or 'review'"),
    start_date: Optional[str] = Query(None, pattern=r"^\d{4}-\d{2}-\d{2}$", description="Start date (YYYY-MM-DD)"),
    end_date: Optional[str] = Query(None, pattern=r"^\d{4}-\d{2}-\d{2}$", description="End date (YYYY-MM-DD)"),
    limit: int = Query(20, ge=1, le=100, description="Max results (1-100)")
):
    """
    List security scans with optional filters

    Example queries:
    - /scans?repo_name=kannavkunal/vulnerable-python-api
    - /scans?scan_mode=patch&limit=10
    - /scans?start_date=2026-06-01&end_date=2026-06-06
    """
    try:
        # Normalize empty strings to None
        repo_name = repo_name.strip() if repo_name else None
        repo_name = None if repo_name == "" else repo_name
        scan_mode = scan_mode.strip() if scan_mode else None
        scan_mode = None if scan_mode == "" else scan_mode
        start_date = start_date.strip() if start_date else None
        start_date = None if start_date == "" else start_date
        end_date = end_date.strip() if end_date else None
        end_date = None if end_date == "" else end_date

        client = get_bq_client()
        if client is None:
            raise HTTPException(status_code=503, detail="BigQuery not available in test mode")

        # Validate repo_name format (prevent SQL injection)
        if repo_name:
            if not re.match(r'^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$', repo_name):
                raise HTTPException(
                    status_code=400,
                    detail="Invalid repo_name format. Must be 'owner/repo'"
                )

        # Build WHERE clauses with parameterized queries to prevent SQL injection
        where_clauses = []
        if repo_name:
            # Escape for BigQuery
            where_clauses.append(f"repo_name = @repo_name")
        if scan_mode:
            where_clauses.append(f"scan_mode = @scan_mode")
        if start_date:
            where_clauses.append(f"DATE(timestamp) >= @start_date")
        if end_date:
            where_clauses.append(f"DATE(timestamp) <= @end_date")

        where_sql = " AND ".join(where_clauses) if where_clauses else "1=1"

        query = f"""
        SELECT
            scan_id,
            timestamp,
            repo_name,
            repo_owner,
            branch,
            scan_mode,
            status,
            trigger_type,
            vulnerabilities_found,
            fixes_applied,
            pr_url,
            pr_number,
            evidence_path,
            llm_model_used
        FROM `{PROJECT_ID}.security_scans.scans`
        WHERE {where_sql}
        ORDER BY timestamp DESC
        LIMIT @limit
        """

        # Build query parameters to prevent SQL injection
        from google.cloud.bigquery import ScalarQueryParameter
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                ScalarQueryParameter("limit", "INT64", limit),
            ]
        )

        if repo_name:
            job_config.query_parameters.append(
                ScalarQueryParameter("repo_name", "STRING", repo_name)
            )
        if scan_mode:
            job_config.query_parameters.append(
                ScalarQueryParameter("scan_mode", "STRING", scan_mode)
            )
        if start_date:
            job_config.query_parameters.append(
                ScalarQueryParameter("start_date", "DATE", start_date)
            )
        if end_date:
            job_config.query_parameters.append(
                ScalarQueryParameter("end_date", "DATE", end_date)
            )

        query_job = client.query(query, job_config=job_config)
        results = query_job.result()

        scans = []
        for row in results:
            scans.append(ScanRecord(
                scan_id=row.scan_id,
                timestamp=row.timestamp.isoformat() if row.timestamp else None,
                repo_name=row.repo_name,
                repo_owner=row.repo_owner,
                branch=row.branch,
                scan_mode=row.scan_mode,
                status=row.status,
                trigger_type=row.trigger_type,
                vulnerabilities_found=row.vulnerabilities_found,
                fixes_applied=row.fixes_applied,
                pr_url=row.pr_url,
                pr_number=row.pr_number,
                evidence_path=row.evidence_path,
                llm_model_used=row.llm_model_used
            ))

        return ScansListResponse(
            total=len(scans),
            scans=scans,
            filters_applied={
                "repo_name": repo_name,
                "scan_mode": scan_mode,
                "start_date": start_date,
                "end_date": end_date,
                "limit": limit
            }
        )

    except Exception as e:
        logger.error(f"Error in /scans endpoint: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to query scans: {str(e)}")


@app.get("/scans/{scan_id}", response_model=ScanRecord)
async def get_scan(
    scan_id: str,
    api_key: str = Depends(verify_api_key)
):
    """
    Get details of a specific scan by scan_id

    Example: /scans/scan-abc12345
    """
    try:
        client = get_bq_client()
        if client is None:
            raise HTTPException(status_code=503, detail="BigQuery not available in test mode")

        query = f"""
        SELECT
            scan_id,
            timestamp,
            repo_name,
            repo_owner,
            branch,
            scan_mode,
            status,
            trigger_type,
            vulnerabilities_found,
            fixes_applied,
            pr_url,
            pr_number,
            evidence_path,
            llm_model_used
        FROM `{PROJECT_ID}.security_scans.scans`
        WHERE scan_id = @scan_id
        LIMIT 1
        """

        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("scan_id", "STRING", scan_id)
            ]
        )

        query_job = client.query(query, job_config=job_config)
        results = list(query_job.result())

        if not results:
            raise HTTPException(status_code=404, detail=f"Scan {scan_id} not found")

        row = results[0]
        return ScanRecord(
            scan_id=row.scan_id,
            timestamp=row.timestamp.isoformat() if row.timestamp else None,
            repo_name=row.repo_name,
            repo_owner=row.repo_owner,
            branch=row.branch,
            scan_mode=row.scan_mode,
            status=row.status,
            trigger_type=row.trigger_type,
            vulnerabilities_found=row.vulnerabilities_found,
            fixes_applied=row.fixes_applied,
            pr_url=row.pr_url,
            pr_number=row.pr_number,
            evidence_path=row.evidence_path,
            llm_model_used=row.llm_model_used
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch scan: {str(e)}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
