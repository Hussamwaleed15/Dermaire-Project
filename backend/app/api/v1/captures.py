from datetime import datetime, timezone
from uuid import uuid4, uuid5, NAMESPACE_URL
import hashlib
import json
from typing import Literal
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, Header
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool
from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.config import settings
from app.models import Capture, User
from app.services import capture_quality, measurement
from app.services.azure_blob import azure_blob_service
from app.services.image_reconciliation import cleanup_failed_upload
from app.services.image_access import safe_reference
import logging

router = APIRouter(prefix="/captures", tags=["Guided capture quality"])


def response(row):
    return {"id": row.id, "state": row.state, "received_at": row.received_at.replace(tzinfo=timezone.utc),
            "source": row.source, "view": row.view, "quality": row.quality,
            "storage": row.storage, "image_reference": safe_reference(row.image_blob_name),
            "provenance": {"timestamp": "server_received_not_camera_time", "source": "client_reported",
                           "view": "client_reported", "server_version": row.server_version,
                           "quality": "server_computed"}}


@router.post("", status_code=201)
async def create_capture(photo: UploadFile = File(...), source: Literal["camera", "upload"] = Form("upload"),
                         view: Literal["front"] = Form("front"),
                         idempotency_key: str | None = Header(None, max_length=128),
                         current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    received_at = datetime.now(timezone.utc)
    data = await photo.read(capture_quality.RULES.max_bytes + 1)
    # The authenticated owner lock serializes retries with deletion (PostgreSQL).
    db.query(User).filter_by(id=current_user.id).with_for_update().first()
    fingerprint = hashlib.sha256(json.dumps([source, view, photo.content_type, hashlib.sha256(data).hexdigest()]).encode()).hexdigest()
    identifier = str(uuid5(NAMESPACE_URL, json.dumps(["capture-v1", current_user.id, idempotency_key or fingerprint])))
    existing = db.query(Capture).filter_by(id=identifier, user_id=current_user.id).first()
    if existing and existing.quality.get("request_fingerprint") != fingerprint:
        raise HTTPException(409, "Idempotency key belongs to a different upload.")
    if existing and (existing.storage == "azure_blob" or existing.state == "rejected" or not azure_blob_service.is_live):
        result = response(existing)
        if existing.state == "accepted":
            result["measurement"] = measurement.response(measurement.build(db, existing))
        return result
    image, orientation = capture_quality.decode_image(data, photo.content_type)
    try:
        quality = await run_in_threadpool(capture_quality.assess, image, orientation)
    except Exception:
        raise HTTPException(503, "Quality checking unavailable. No capture was saved; retry later.")
    finally:
        image.close()
    quality["request_fingerprint"] = fingerprint
    row = existing or Capture(id=identifier, user_id=current_user.id, source=source, view=view, state=quality["decision"],
                  quality=quality, storage="not_persisted", server_version=settings.VERSION, received_at=received_at)
    blob = None
    try:
        if row.state == "accepted" and not azure_blob_service.is_live and settings.ENVIRONMENT in {"production", "staging"}:
            raise RuntimeError("Production image storage is not configured")
        db.query(User).filter_by(id=current_user.id).with_for_update().first()
        db.add(row)
        db.flush()
        if row.state == "accepted":
            pixels, _ = capture_quality.decode_image(data, photo.content_type)
            try:
                measured = await run_in_threadpool(measurement.build, db, row, pixels)
            finally:
                pixels.close()
        if row.state == "accepted" and azure_blob_service.is_live:
            # Re-encode: strip EXIF/GPS and never preserve untrusted filenames or metadata.
            from io import BytesIO
            image, _ = capture_quality.decode_image(data, photo.content_type)
            buffer = BytesIO()
            image.info.clear()
            image.save(buffer, format="PNG")
            image.close()
            # A retry must never reuse a key retired by a cleanup intent.
            blob = f"skin_photos/{current_user.id}/{current_user.id}_{uuid4()}.png"
            await run_in_threadpool(azure_blob_service.upload_capture, blob, buffer.getvalue())
            row.image_blob_name = blob
            row.storage = "azure_blob"
        result = response(row)
        if row.state == "accepted":
            result["measurement"] = measurement.response(measured)
        db.commit()
    except Exception:
        db.rollback()
        if blob:
            try:
                await run_in_threadpool(cleanup_failed_upload, db, azure_blob_service, current_user.id, blob)
            except Exception:
                logging.getLogger(__name__).warning("Image cleanup pending; run orphan reconciliation after recovery")
        raise HTTPException(503, "Capture could not be saved. Refresh history before retrying.")
    return result


@router.get("")
def history(state: Literal["accepted", "rejected"] | None = None, limit: int = 50,
            current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not 1 <= limit <= 100:
        raise HTTPException(422, "Limit must be between 1 and 100.")
    query = db.query(Capture).filter_by(user_id=current_user.id)
    if state:
        query = query.filter_by(state=state)
    return [response(row) for row in query.order_by(Capture.received_at.desc(), Capture.id.desc()).limit(limit)]


@router.get("/{capture_id}")
def get_capture(capture_id: str, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.query(Capture).filter_by(id=capture_id, user_id=current_user.id).first()
    if not row:
        raise HTTPException(404, "Capture not found.")
    return response(row)


@router.get("/{capture_id}/image")
def get_image(capture_id: str, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    from app.services.image_access import image_response
    row = db.query(Capture).filter_by(id=capture_id).first()
    return image_response(db, current_user, row)
