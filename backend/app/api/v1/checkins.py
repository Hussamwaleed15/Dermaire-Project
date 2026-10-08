from datetime import datetime, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, UploadFile, File, Form, status, HTTPException, Header
from starlette.concurrency import run_in_threadpool
from io import BytesIO
from uuid import uuid4, uuid5, NAMESPACE_URL
import hashlib
import json
from app.services import capture_quality
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.api.deps import get_current_user
from app.models import User, CheckIn, Experiment, DailyContext, AuditLog
from app.schemas import CheckInResponse, CheckInReport
from pydantic import ValidationError
from app.core.exceptions import DermaireException, EntityNotFoundException
from app.services.baseline import baseline_snapshot, confirmed_measurement
import math
from app.services.azure_blob import azure_blob_service
from app.services.image_reconciliation import cleanup_failed_upload
from app.services.image_access import safe_reference
import logging
from app.services.azure_vision import azure_vision_service

router = APIRouter(prefix="/checkins", tags=["Daily Skin Check-ins & Journal"])

@router.get("", response_model=List[CheckInResponse])
def get_checkins_history(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    checkins = db.query(CheckIn).filter(
        CheckIn.user_id == current_user.id
    ).order_by(CheckIn.created_at.desc(), CheckIn.id.desc()).all()

    results = []
    for c in checkins:
        # Quarantine legacy default/simulated rows, without inventing provenance.
        if not c.observation and not confirmed_measurement(c):
            continue
        results.append(CheckInResponse(
            id=c.id,
            user_id=c.user_id,
            experiment_id=c.experiment_id,
            date_str=c.date_str,
            time_of_day=c.time_of_day,
            hydration_score=c.hydration_score,
            texture_score=c.texture_score,
            redness_score=c.redness_score,
            notes=c.notes,
            image_sas_url=None,
            image_endpoint=f"/api/v1/checkins/{c.id}/image" if safe_reference(c.image_blob_name) else None,
            storage=("azure_blob" if (c.ai_vision_analysis or {}).get("image_storage") == "azure_blob" else "legacy_unverified") if c.image_blob_name else "not_persisted",
            image_reference=safe_reference(c.image_blob_name),
            ai_vision_analysis=c.ai_vision_analysis,
            observation=c.observation,
            tokens_earned=0,
            created_at=c.created_at
        ))
    return results

@router.post("", response_model=CheckInResponse, status_code=status.HTTP_201_CREATED)
async def submit_daily_checkin(
    time_of_day: str = Form("Morning"),
    hydration_score: Optional[float] = Form(None),
    texture_score: Optional[float] = Form(None),
    redness_score: Optional[float] = Form(None),
    notes: Optional[str] = Form(None),
    experiment_id: Optional[str] = Form(None),
    photo: Optional[UploadFile] = File(None),
    report: Optional[str] = Form(None),
    idempotency_key: str | None = Header(None, max_length=128),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    blob_name = None
    ai_analysis = {"measurement_source": "manual"}
    user_report = None
    if report is not None:
        try:
            user_report = CheckInReport.model_validate_json(report)
            user_report.symptoms = list(dict.fromkeys(user_report.symptoms))
        except ValidationError:
            raise DermaireException("Invalid structured report.", error_code="INVALID_REPORT", status_code=422)
    if time_of_day not in ("Morning", "Evening") or (notes and len(notes) > 1500):
        raise DermaireException("Invalid check-in fields.", error_code="INVALID_CHECKIN", status_code=422)
    exp = None
    if experiment_id:
        exp = db.query(Experiment).filter(Experiment.id == experiment_id,
                                         Experiment.user_id == current_user.id).first()
        if not exp:
            raise EntityNotFoundException("Experiment", experiment_id)
    has_photo = bool(photo and photo.filename)
    scores = (hydration_score, texture_score, redness_score)
    has_scores = any(v is not None for v in scores)
    valid_scores = all(v is not None and math.isfinite(v) and 0 <= v <= 100 for v in scores)
    if (has_scores and not valid_scores) or (not has_photo and not valid_scores and not user_report):
        raise DermaireException("Provide three valid measurements or a photo.",
                               error_code="MEASUREMENT_REQUIRED", status_code=422)
    if not has_scores and not has_photo:
        ai_analysis = {"measurement_source": "none"}

    identifier = None
    normalized = None
    if photo and photo.filename:
        photo_bytes = await photo.read(capture_quality.RULES.max_bytes + 1)
        image, orientation = capture_quality.decode_image(photo_bytes, photo.content_type)
        try:
            try:
                quality = await run_in_threadpool(capture_quality.assess, image, orientation)
            except Exception:
                raise HTTPException(503, "Quality checking unavailable. No check-in was saved.")
            if quality["decision"] != "accepted":
                raise HTTPException(422, "Photo quality rejected. No image or check-in was saved.")
            buffer = BytesIO()
            image.info.clear()
            image.save(buffer, format="PNG")
            normalized = buffer.getvalue()
        finally:
            image.close()
        db.query(User).filter_by(id=current_user.id).with_for_update().first()
        fingerprint = hashlib.sha256(json.dumps([time_of_day, notes, experiment_id,
            user_report.model_dump() if user_report else None, photo.content_type,
            hashlib.sha256(photo_bytes).hexdigest()], sort_keys=True).encode()).hexdigest()
        identifier = str(uuid5(NAMESPACE_URL, json.dumps(["checkin-image-v1", current_user.id,
            idempotency_key or (datetime.now(timezone.utc).date().isoformat() + fingerprint)])))
        existing = db.query(CheckIn).filter_by(id=identifier, user_id=current_user.id).first()
        if existing and (existing.ai_vision_analysis or {}).get("image_request_fingerprint") != fingerprint:
            raise HTTPException(409, "Idempotency key belongs to a different upload.")
        if existing:
            result = CheckInResponse.model_validate(existing)
            result.image_endpoint = f"/api/v1/checkins/{existing.id}/image" if safe_reference(existing.image_blob_name) else None
            result.storage = "azure_blob" if existing.image_blob_name else "not_persisted"
            result.image_reference = safe_reference(existing.image_blob_name)
            return result
        ai_analysis = await run_in_threadpool(azure_vision_service.analyze_skin_image, normalized)
        values = [ai_analysis.get(k) for k in ("estimated_hydration_score",
                  "surface_texture_score", "erythema_redness_score")]
        if ai_analysis.get("azure_vision_status") != "ANALYSIS_COMPLETE" or not all(
                isinstance(v, (int, float)) and math.isfinite(v) and 0 <= v <= 100 for v in values):
            raise DermaireException("Photo measurement unavailable. No check-in was saved.",
                                   error_code="MEASUREMENT_UNAVAILABLE", status_code=503)
        hydration_score, texture_score, redness_score = values
        ai_analysis["measurement_source"] = "image_proxy"
        ai_analysis["image_storage"] = "azure_blob"
        ai_analysis["image_request_fingerprint"] = fingerprint
        # Keep request idempotency in the DB; storage attempts have distinct keys.
        blob_name = f"skin_photos/{current_user.id}/{current_user.id}_{uuid4()}.png"

    if exp and exp.engine_version != 2 and exp.status == "active" and (valid_scores or has_photo):
        exp.current_day = min(exp.target_days, exp.current_day + 1)
        baseline = baseline_snapshot(db, current_user.id, before=exp.created_at)
        for metric, score in (("redness", redness_score), ("texture", texture_score),
                              ("hydration", hydration_score)):
            reference = baseline["metrics"].get(metric, {}).get("mean")
            delta = round((score - reference) / reference * 100, 1) if reference else None
            setattr(exp, metric + "_delta_percent", delta)

    now = datetime.now(timezone.utc)
    context = db.query(DailyContext).filter_by(user_id=current_user.id, date=now.date()).first()
    source = ai_analysis["measurement_source"]
    observation = {
        "schema_version": 1,
        "user_reported": user_report.model_dump() if user_report else None,
        "daily_context_date": now.date().isoformat(),
        "daily_context_id": context.id if context else None,
        "provenance": {"created_at": "server_recorded", "report": "user_reported" if user_report else "not_reported",
            "notes": "user_reported" if notes else "not_reported",
            "measurements": {"manual": "user_reported", "image_proxy": "system_derived", "none": "not_recorded"}[source],
            "photo": "user_uploaded" if blob_name else "not_recorded",
            "daily_context_date": "server_derived", "daily_context": "user_reported" if context else "not_recorded"},
    }
    checkin = CheckIn(
        user_id=current_user.id,
        experiment_id=experiment_id,
        date_str=now.strftime("%b %d, %Y"),
        time_of_day=time_of_day,
        hydration_score=hydration_score,
        texture_score=texture_score,
        redness_score=redness_score,
        notes=notes,
        image_blob_name=blob_name,
        ai_vision_analysis=ai_analysis,
        observation=observation,
        created_at=now
    )
    if identifier:
        checkin.id = identifier
    try:
        db.add(checkin)
        db.flush()  # Validate database fields before any external write.
        if blob_name:
            await run_in_threadpool(azure_blob_service.upload_capture, blob_name, normalized)
        db.add(AuditLog(actor_id=current_user.id, action="CHECKIN_COMPLETED", target_resource="checkins",
                        details={"checkin_id": checkin.id, "has_photo": bool(blob_name)}))
        db.commit()
    except Exception:
        db.rollback()
        if blob_name:
            try:
                await run_in_threadpool(cleanup_failed_upload, db, azure_blob_service, current_user.id, blob_name)
            except Exception:
                logging.getLogger(__name__).warning("Image cleanup pending; run orphan reconciliation after recovery")
        raise HTTPException(503, "Check-in could not be saved. Refresh history before retrying.")

    return CheckInResponse(
        id=checkin.id,
        user_id=checkin.user_id,
        experiment_id=checkin.experiment_id,
        date_str=checkin.date_str,
        time_of_day=checkin.time_of_day,
        hydration_score=checkin.hydration_score,
        texture_score=checkin.texture_score,
        redness_score=checkin.redness_score,
        notes=checkin.notes,
        image_sas_url=None,
        image_endpoint=f"/api/v1/checkins/{checkin.id}/image" if blob_name else None,
        storage="azure_blob" if blob_name else "not_persisted",
        image_reference=blob_name,
        ai_vision_analysis=checkin.ai_vision_analysis,
        observation=checkin.observation,
        tokens_earned=0,
        created_at=checkin.created_at
    )


@router.get("/{checkin_id}/image")
def get_image(checkin_id: str, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    from app.services.image_access import image_response
    return image_response(db, current_user, db.query(CheckIn).filter_by(id=checkin_id).first())
