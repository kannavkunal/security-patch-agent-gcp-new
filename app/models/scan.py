"""
Scan Model - Represents a complete security scan execution
"""
from typing import Optional, Dict, List
from pydantic import BaseModel, Field
from datetime import datetime
from enum import Enum


class ScanMode(str, Enum):
    """Scan execution mode"""
    REVIEW = "review"  # Comment on existing PR
    PATCH = "patch"    # Create new PR with fixes


class ScanStatus(str, Enum):
    """Scan execution status"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class TriggerType(str, Enum):
    """What triggered the scan"""
    API = "api"               # Manual API call
    PR_EVENT = "pr_event"     # GitHub webhook
    SCHEDULED = "scheduled"   # Cron job


class Scan(BaseModel):
    """
    Represents a complete security scan of a repository.

    Tracks the entire scan lifecycle from trigger to PR creation.
    """
    # Identity
    scan_id: str = Field(description="Unique scan ID (scan-abc123)")
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    # Repository Info
    repo_url: str
    repo_name: str = Field(description="Extracted from URL")
    repo_owner: str = Field(description="GitHub username/org")
    branch: str = Field(default="main")
    commit_sha: Optional[str] = None

    # Execution
    scan_mode: ScanMode
    status: ScanStatus = Field(default=ScanStatus.PENDING)
    trigger_type: TriggerType

    # Results
    vulnerabilities_found: int = Field(default=0)
    fixes_applied: int = Field(default=0)
    pr_url: Optional[str] = None
    pr_number: Optional[int] = None
    pr_merged: bool = Field(default=False)
    pr_merge_date: Optional[datetime] = None

    # Performance
    duration_seconds: Optional[int] = None
    phase_durations: Optional[Dict[str, int]] = Field(
        None,
        description="Time spent in each phase {phase1: 10, phase2: 45, ...}"
    )

    # LLM Context (KEY INNOVATION)
    llm_model_used: str = Field(default="gemini-2.5-pro")
    llm_tokens_used: Optional[int] = None
    llm_context_included: bool = Field(
        default=False,
        description="Was repository history provided to LLM?"
    )
    llm_context_scan_ids: Optional[List[str]] = Field(
        None,
        description="Which past scans were in LLM context"
    )

    # Summaries (JSON strings for BigQuery)
    findings_summary: Optional[str] = None  # JSON array of VulnerabilitySummary
    patches_summary: Optional[str] = None   # JSON array of PatchSummary

    class Config:
        use_enum_values = True


class ScanRequest(BaseModel):
    """API request to trigger a scan"""
    repo_url: str = Field(description="GitHub repository URL")
    mode: ScanMode = Field(default=ScanMode.PATCH)
    branch: str = Field(default="main")


class ScanResponse(BaseModel):
    """API response after triggering scan"""
    scan_id: str
    status: str
    message: str
