"""
Patch Model - Represents a generated code fix
"""
from typing import Optional, List
from pydantic import BaseModel, Field
from datetime import datetime


class Confidence(str):
    """Confidence level in patch correctness"""
    HIGH = "HIGH"      # >90% confident
    MEDIUM = "MEDIUM"  # 70-90% confident
    LOW = "LOW"        # <70% confident


class ValidationStatus(str):
    """Patch validation status"""
    PASSED = "passed"    # Tests passed, vuln re-scan clean
    FAILED = "failed"    # Tests failed or vuln still present
    SKIPPED = "skipped"  # No tests available


class Patch(BaseModel):
    """
    Represents a generated code fix with LLM reasoning.

    Includes full context about why the patch was generated,
    what alternatives were considered, and validation results.
    """
    # Identity
    patch_id: str = Field(description="Unique ID (P-001)")
    scan_id: str = Field(description="Parent scan ID")
    vulnerability_id: str = Field(description="Which vulnerability this fixes")

    # Location
    file_path: str = Field(description="File being patched")
    vulnerability_type: str = Field(description="SQL Injection, XSS, etc.")

    # Code Changes
    original_code: str = Field(description="Original vulnerable code")
    patched_code: str = Field(description="Fixed code")
    diff: str = Field(description="Git-style diff")
    lines_changed: int = Field(default=0, description="Number of lines modified")

    # LLM Reasoning (Critical for learning)
    reasoning: str = Field(description="Why this fix was chosen")
    alternatives_considered: Optional[str] = Field(
        None,
        description="What other approaches were evaluated"
    )
    confidence: str = Field(description="HIGH, MEDIUM, or LOW")

    # Validation
    validation_status: ValidationStatus
    test_results: Optional[str] = Field(None, description="Test execution output")

    # Outcome Tracking (for LLM context memory)
    accepted: bool = Field(default=False, description="Was PR merged?")
    modified_before_merge: bool = Field(default=False, description="Did team modify it?")
    rejection_reason: Optional[str] = Field(
        None,
        description="Why was PR rejected? (Learn from this!)"
    )

    # Metadata
    applied_at: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        use_enum_values = True


class PatchSummary(BaseModel):
    """
    Compact summary for LLM context and BigQuery storage.
    Used in patches_summary JSON field.
    """
    type: str
    file: str
    description: str
    lines_changed: int = 0

    @classmethod
    def from_patch(cls, patch: Patch):
        # Truncate description to first sentence or 200 chars
        desc = patch.reasoning.split('.')[0][:200]
        return cls(
            type=patch.vulnerability_type,
            file=patch.file_path,
            description=desc,
            lines_changed=patch.lines_changed
        )
