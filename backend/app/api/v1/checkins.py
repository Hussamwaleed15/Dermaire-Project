from datetime import datetime, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, UploadFile, File, Form, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.api.deps import get_current_user, record_audit
from app.models import User, CheckIn, Experiment, DailyContext
from app.schemas import CheckInResponse, CheckInReport
from pydantic import ValidationError
from app.core.exceptions import DermaireException, EntityNotFoundException
from app.services.baseline import baseline_snapshot, confirmed_measurement
import math
from app.services.azure_blob import azure_blob_service
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
        sas_url = None
        if c.image_blob_name:
            sas_url = azure_blob_service.generate_sas_url(c.image_blob_name)
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
            image_sas_url=sas_url,
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
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    blob_name = None
    sas_url = None
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

    if photo and photo.filename:
        photo_bytes = await photo.read()
        ai_analysis = azure_vision_service.analyze_skin_image(photo_bytes)
        values = [ai_analysis.get(k) for k in ("estimated_hydration_score",
                  "surface_texture_score", "erythema_redness_score")]
        if ai_analysis.get("azure_vision_status") != "ANALYSIS_COMPLETE" or not all(
                isinstance(v, (int, float)) and math.isfinite(v) and 0 <= v <= 100 for v in values):
            raise DermaireException("Photo measurement unavailable. No check-in was saved.",
                                   error_code="MEASUREMENT_UNAVAILABLE", status_code=503)
        hydration_score, texture_score, redness_score = values
        ai_analysis["measurement_source"] = "image_proxy"
        blob_name, sas_url = azure_blob_service.upload_image(
            file_bytes=photo_bytes, original_filename=photo.filename,
            content_type=photo.content_type or "image/jpeg", owner_id=current_user.id)

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
    db.add(checkin)

    db.commit()
    db.refresh(checkin)

    record_audit(db, current_user.id, "CHECKIN_COMPLETED", "checkins", {
        "checkin_id": checkin.id,
        "has_photo": bool(blob_name)
    })

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
        image_sas_url=sas_url,
        ai_vision_analysis=checkin.ai_vision_analysis,
        observation=checkin.observation,
        tokens_earned=0,
        created_at=checkin.created_at
    )
