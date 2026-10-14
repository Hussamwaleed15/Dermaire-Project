"""Explicit opt-in protection; legacy writes cannot bypass an opted-in product."""
import re
from fastapi import HTTPException
from sqlalchemy.orm.exc import StaleDataError

def enforce(product, if_match):
    if if_match is None:
        if product.revision_protected:
            raise HTTPException(428, "This product requires If-Match with its current revision")
        return
    if not isinstance(if_match, str) or not re.fullmatch(r'"[1-9][0-9]{0,9}"', if_match):
        raise HTTPException(422, 'If-Match must be a strong quoted positive decimal revision')
    expected = int(if_match[1:-1])
    if expected > 2147483647:
        raise HTTPException(422, "Revision is out of range")
    if expected != product.revision:
        raise HTTPException(412, "Product revision changed; read the current product")

def commit(db):
    try:
        db.commit()
    except StaleDataError:
        db.rollback()
        raise HTTPException(412, "Product changed or was deleted; reconcile before retrying")
    except Exception:
        db.rollback()
        raise HTTPException(503, "Product mutation outcome unavailable; reconcile before retrying")
