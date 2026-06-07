"""
Models package - Data structures for scans, vulnerabilities, and patches
"""
from .vulnerability import (
    Vulnerability,
    VulnerabilitySummary,
    EvidenceTier,
    VerificationLevel,
    Severity,
)
from .patch import (
    Patch,
    PatchSummary,
    Confidence,
    ValidationStatus,
)
from .scan import (
    Scan,
    ScanMode,
    ScanStatus,
    TriggerType,
    ScanRequest,
    ScanResponse,
)

__all__ = [
    # Vulnerability
    "Vulnerability",
    "VulnerabilitySummary",
    "EvidenceTier",
    "VerificationLevel",
    "Severity",
    # Patch
    "Patch",
    "PatchSummary",
    "Confidence",
    "ValidationStatus",
    # Scan
    "Scan",
    "ScanMode",
    "ScanStatus",
    "TriggerType",
    "ScanRequest",
    "ScanResponse",
]
