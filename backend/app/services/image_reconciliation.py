"""Owner-serialized orphan reconciliation; use a dedicated DB session."""
import re
from datetime import datetime, timedelta, timezone
from app.models import User, Capture, CheckIn


def reconcile(db, storage, apply=False, minimum_age_hours=24):
    if minimum_age_hours < 24:
        raise ValueError("Orphan grace period must be at least 24 hours")
    storage.require_private()
    cutoff = datetime.now(timezone.utc) - timedelta(hours=minimum_age_hours)
    counts = {"candidates": 0, "deleted": 0}
    for blob in storage.container_client.list_blobs(name_starts_with="skin_photos/"):
        match = re.fullmatch(r"skin_photos/([A-Za-z0-9-]+)/\1_([a-f0-9-]{36})\.png", blob.name)
        if not match or not blob.last_modified or blob.last_modified >= cutoff:
            continue
        owner = match.group(1)
        db.query(User).filter_by(id=owner).with_for_update().first()
        referenced = any(db.query(model.id).filter_by(image_blob_name=blob.name).first()
                         for model in (Capture, CheckIn))
        if not referenced:
            counts["candidates"] += 1
            if apply:
                storage.delete_image(blob.name)
                counts["deleted"] += 1
        db.rollback()
    return counts



def cleanup_failed_upload(db, storage, owner_id, blob_name):
    """Reacquire the owner lock after rollback; a committed retry wins over cleanup."""
    try:
        db.query(User).filter_by(id=owner_id).with_for_update().first()
        referenced = any(db.query(model.id).filter_by(image_blob_name=blob_name).first()
                         for model in (Capture, CheckIn))
        if not referenced:
            storage.delete_image(blob_name)
    finally:
        db.rollback()
