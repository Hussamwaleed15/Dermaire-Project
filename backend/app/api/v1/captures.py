from datetime import datetime, timezone
from uuid import uuid4
from typing import Literal
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, Response
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool
from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.config import settings
from app.models import Capture, User
from app.services import capture_quality
from app.services.azure_blob import azure_blob_service

router = APIRouter(prefix="/captures", tags=["Guided capture quality"])


def response(row):
    return {"id": row.id, "state": row.state, "received_at": row.received_at.replace(tzinfo=timezone.utc),
            "source": row.source, "view": row.view, "quality": row.quality,
            "storage": row.storage, "image_reference": row.image_blob_name,
            "provenance": {"timestamp": "server_received_not_camera_time", "source": "client_reported",
                           "view": "client_reported", "server_version": row.server_version,
                           "quality": "server_computed"}}


@router.post("", status_code=201)
async def create_capture(photo: UploadFile = File(...), source: Literal["camera", "upload"] = Form("upload"),
                         view: Literal["front"] = Form("front"),
                         current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    received_at = datetime.now(timezone.utc)
    data = await photo.read(capture_quality.RULES.max_bytes + 1)
    image, orientation = capture_quality.decode_image(data, photo.content_type)
    try:
        quality = await run_in_threadpool(capture_quality.assess, image, orientation)
    except Exception:
        raise HTTPException(503, "Quality checking unavailable. No capture was saved; retry later.")
    finally:
        image.close()
    row = Capture(user_id=current_user.id, source=source, view=view, state=quality["decision"],
                  quality=quality, storage="not_persisted", server_version=settings.VERSION, received_at=received_at)
    blob = None
    try:
        if row.state == "accepted" and azure_blob_service.is_live:
            # Re-encode: strip EXIF/GPS and never preserve untrusted filenames or metadata.
            from io import BytesIO
            image, _ = capture_quality.decode_image(data, photo.content_type)
            buffer = BytesIO()
            image.save(buffer, format="PNG")
            image.close()
            blob = f"skin_photos/{current_user.id}/{current_user.id}_{uuid4()}.png"
            await run_in_threadpool(azure_blob_service.upload_capture, blob, buffer.getvalue())
            row.image_blob_name = blob
            row.storage = "azure_blob"
        db.add(row)
        db.flush()
        result = response(row)
        db.commit()
    except Exception:
        db.rollback()
        if blob:
            try:
                await run_in_threadpool(azure_blob_service.delete_image, blob)
            except Exception:
                # Ownership namespace is retained for account-deletion retry.
                pass
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
    row = db.query(Capture).filter_by(id=capture_id, user_id=current_user.id).first()
    if not row or not row.image_blob_name:
        raise HTTPException(404, "Capture image not available.")
    try:
        data = azure_blob_service.read_capture(row.image_blob_name)
    except Exception:
        raise HTTPException(503, "Image storage unavailable; retry later.")
    return Response(data, media_type="image/png", headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"})
