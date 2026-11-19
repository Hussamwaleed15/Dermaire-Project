"""Public, non-secret build and schema compatibility metadata."""

from datetime import datetime, timezone
import re

from app.core.config import settings


REQUIRED_ALEMBIC_REVISION = "20261024_14"
_GIT_SHA = re.compile(r"^[0-9a-fA-F]{40}$")


def _normalized_timestamp(value: str) -> str | None:
    try:
        parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except (AttributeError, TypeError, ValueError):
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def build_metadata() -> dict:
    """Return only validated provenance; invalid raw settings are never echoed."""
    sha = settings.BUILD_GIT_SHA.strip().lower()
    timestamp = _normalized_timestamp(settings.BUILD_TIMESTAMP)
    available = bool(_GIT_SHA.fullmatch(sha) and timestamp)
    return {
        "available": available,
        "git_commit_sha": sha if available else None,
        "build_timestamp": timestamp if available else None,
        "api_version": settings.VERSION,
        "required_alembic_revision": REQUIRED_ALEMBIC_REVISION,
    }


def schema_is_compatible(revisions: list[str]) -> bool:
    """A managed deployment must have exactly the schema revision it was built for."""
    return revisions == [REQUIRED_ALEMBIC_REVISION]
