"""Configuration revisions: explicit per-resource opt-in and ORM all-writer CAS."""
import re
from fastapi import HTTPException, Request
from sqlalchemy.orm.exc import StaleDataError


def header(request: Request, name="If-Match"):
    values = request.headers.getlist(name)
    if len(values) > 1:
        raise HTTPException(422, f"Duplicate {name} headers are unsupported")
    return values[0] if values else None


def enforce(row, value):
    if value is None:
        if row.revision_protected:
            raise HTTPException(428, "This resource requires its current revision")
        return
    if not isinstance(value, str) or not re.fullmatch(r'"[1-9][0-9]{0,9}"', value):
        raise HTTPException(422, "Revision must be a strong quoted positive decimal")
    expected = int(value[1:-1])
    if expected > 2147483647:
        raise HTTPException(422, "Revision is out of range")
    if expected != row.revision:
        raise HTTPException(412, "Resource revision changed; reload before retrying")


def reserve(db, row, value):
    enforce(row, value)
    if value is not None:
        row.revision_protected = True
    # Even no-op writes reserve a new revision before any dependent effects.
    row.revision += 1
    try:
        db.flush()
    except StaleDataError:
        db.rollback()
        raise HTTPException(412, "Resource changed or was deleted; reconcile before retrying")
    except Exception:
        db.rollback()
        raise HTTPException(503, "Revision reservation unavailable; reconcile before retrying")


def etag(response, row):
    response.headers["ETag"] = f'"{row.revision}"'
