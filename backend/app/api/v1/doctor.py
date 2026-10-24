from datetime import datetime, timedelta, timezone
from typing import List, Optional
from fastapi import APIRouter, Body, Depends, Query, status, HTTPException, Header, Response
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import create_doctor_access_token, decode_token, credential_stamp
from app.core.exceptions import (
    PermissionDeniedException, DermaireException
)
from app.api.deps import require_role, get_token_payload
from app.models import User, DoctorPatientAccess, ClinicalNote, CheckIn, Experiment, Product, DoctorReviewAction, AuditLog, gen_uuid
from app.services import clinical_attempts, grant_attempts
from app.services.doctor_consent import consent_of
from app.services.doctor_loop import authorize, save, flush_clinical, access_out, timeline, review_status, reviews, review_out
from app.schemas.doctor_loop import (ReviewActionCreate, ReviewActionOut, ReviewStatusOut,
    DoctorPatientDetailOut, DoctorTimelineOut, AccessGrantOut)
from app.services.safety import evaluate_safety
from app.schemas import (
    GenerateQrRequest, GenerateQrResponse, ClaimAccessRequest, DoctorPatientOut,
    ClinicalNoteCreate, ClinicalNoteOut
)

router = APIRouter(prefix="/doctor", tags=["Doctor Portal, QR Access & Audit"])

@router.post("/generate-qr", response_model=GenerateQrResponse)
def generate_doctor_qr_access(
    payload: GenerateQrRequest | None = Body(None),
    minutes_valid: int = Query(60, ge=15, le=1440),
    current_user: User = Depends(require_role(["patient"])),
    session: dict = Depends(get_token_payload),
    db: Session = Depends(get_db),
    response: Response = None,
    idempotency_key: list[str] | None = Header(None),
):
    response = response or Response()
    attempt, previous = grant_attempts.begin(db, current_user.id, 'issue', idempotency_key,
        {"payload": payload.model_dump(mode="json") if payload else None,
         "minutes_valid": minutes_valid, "session_jti": session["jti"]}, response)
    if previous is not None:
        return previous
    # Old clients retain view-only generation; export always needs separate intent
    # and a selected real clinician. Neither query strings nor claims can expand it.
    export = payload.export_consent if payload else False
    doctor_id = payload.doctor_id if payload else None
    if export and not doctor_id:
        raise HTTPException(422, "Export consent requires a selected clinician")
    if doctor_id and not db.query(User).filter_by(id=doctor_id, role="doctor").first():
        raise HTTPException(404, "Selected clinician unavailable")
    access_id = gen_uuid()
    scopes = ["VIEW", "EXPORT"] if export else ["VIEW"]
    # Keep QR within the existing VARCHAR(512); private purpose/session intent
    # is an atomic server audit receipt, not additional bearer-token content.
    token = create_doctor_access_token(current_user.id, minutes_valid=minutes_valid,
        consent={"version": 2, "access_id": access_id})
    expires_at = datetime.fromtimestamp(decode_token(token)["exp"], timezone.utc)

    access_record = DoctorPatientAccess(
        id=access_id,
        doctor_id=doctor_id,
        patient_id=current_user.id,
        access_token=token,
        status="pending",
        export_consent=export,
        granted_by=current_user.id,
        expires_at=expires_at
    )
    db.add(access_record)
    db.add(AuditLog(actor_id=current_user.id, action="DOCTOR_QR_GENERATED", target_resource="doctor_patient_access", details={
        "access_id": access_record.id,
        "expires_at": expires_at.isoformat(),
        "patient_id": current_user.id,
        "doctor_id": doctor_id, "scopes": scopes, "consent_version": 2,
        "credential": credential_stamp(current_user.hashed_password), "session_jti": session["jti"]
    }))
    flush_clinical(db)
    result = GenerateQrResponse(
        access_token=token,
        qr_payload=f"dermaire://doctor-access?token={token}",
        expires_at=expires_at,
        instructions="Present this single-use code to your clinician. Access is temporary and revocable; export requires separate explicit consent.",
        access=access_out(access_record, db)
    )
    grant_attempts.stage(db, attempt, access_record.id, result.model_dump(mode="json"), response)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(503, "Consent action unconfirmed; reconcile original attempt key") from None

    return result

@router.post("/claim", status_code=status.HTTP_200_OK)
def claim_patient_access(
    payload: ClaimAccessRequest,
    current_doctor: User = Depends(require_role(["doctor"])),
    db: Session = Depends(get_db),
    response: Response = None,
    idempotency_key: list[str] | None = Header(None),
):
    response = response or Response()
    idempotency_key = clinical_attempts.key(idempotency_key)
    try:
        decoded = decode_token(payload.access_token)
        patient_id = decoded.get("patient_id")
        if decoded.get("type") != "doctor_qr_access" or not patient_id:
            raise DermaireException("Invalid QR access token payload.")
    except Exception:
        raise DermaireException("QR access code has expired or is invalid.")

    patient = db.query(User).filter_by(id=patient_id, role="patient").with_for_update().first()
    if not patient:
        raise PermissionDeniedException("Patient access is unavailable")
    access_record = db.query(DoctorPatientAccess).filter(
        DoctorPatientAccess.access_token == payload.access_token,
        DoctorPatientAccess.patient_id == patient_id
    ).with_for_update().first()
    if not access_record or access_record.status not in ("pending", "active"):
        raise DermaireException("This access code is no longer valid or has been revoked by the patient.")

    if access_record.expires_at.replace(tzinfo=timezone.utc) < datetime.now(timezone.utc):
        raise DermaireException("This clinical access code has expired.")

    if access_record.doctor_id and access_record.doctor_id != current_doctor.id:
        raise PermissionDeniedException("This access code is already assigned to another clinician.")

    intent = consent_of(access_record)
    if (not intent or intent.get("credential") != credential_stamp(patient.hashed_password)
            or not intent.get("session_jti") or db.query(AuditLog).filter_by(
                actor_id=patient_id, action="SESSION_REVOKED", target_resource=intent["session_jti"]).first()):
        raise PermissionDeniedException("Patient consent is no longer available; request a new code")
    attempt, previous = clinical_attempts.begin(db, current_doctor.id, patient_id, access_record,
        'claim', idempotency_key, payload, response)
    if previous is not None:
        return previous
    if access_record.status != "pending" or access_record.claimed_at is not None:
        raise HTTPException(409, "Access code already claimed; refresh current access")
    # A conditional transition prevents replay even on DBs without row locks.
    claimed_at = datetime.now(timezone.utc)
    changed = db.query(DoctorPatientAccess).filter(
        DoctorPatientAccess.id == access_record.id,
        DoctorPatientAccess.status == "pending",
        DoctorPatientAccess.claimed_at.is_(None),
        DoctorPatientAccess.revoked_at.is_(None),
        DoctorPatientAccess.expires_at > claimed_at,
    ).update({"doctor_id": current_doctor.id, "status": "active", "claimed_at": claimed_at}, synchronize_session=False)
    if changed != 1:
        db.rollback()
        raise HTTPException(409, "Access changed; request current access")
    db.refresh(access_record)
    result = {"success": True, "message": "Patient access granted.", "access": access_out(access_record, db)}
    clinical_attempts.stage(db, attempt, access_record.id, result, response)
    save(db, current_doctor.id, "PATIENT_ACCESS_CLAIMED", "doctor_patient_access", {
        "patient_id": patient_id,
        "doctor_id": current_doctor.id,
        "access_id": access_record.id
    })
    return result

@router.delete("/revoke/{patient_id}", status_code=status.HTTP_200_OK)
def revoke_patient_access(
    patient_id: str,
    current_user: User = Depends(require_role(["patient"])),
    db: Session = Depends(get_db),
    response: Response = None,
    idempotency_key: list[str] | None = Header(None),
):
    response = response or Response()
    # Patient can revoke their own access
    if current_user.id != patient_id:
        raise PermissionDeniedException("You can only revoke access for your own patient records.")

    attempt, previous = grant_attempts.begin(db, current_user.id, 'revoke_all', idempotency_key,
        {"patient_id": patient_id}, response)
    if previous is not None:
        return previous
    records = db.query(DoctorPatientAccess).filter(
        DoctorPatientAccess.patient_id == patient_id,
        DoctorPatientAccess.status.in_(["active", "pending"])
    ).with_for_update().all()
    for r in records:
        r.status = "revoked"
        r.revoked_at = datetime.now(timezone.utc)
        r.revoked_by = current_user.id
    result = {"success": True, "message": "Clinician access revoked immediately."}
    grant_attempts.stage(db, attempt, patient_id, result, response)
    save(db, current_user.id, "PATIENT_ACCESS_REVOKED", "doctor_patient_access", {"patient_id": patient_id, "access_ids": [r.id for r in records]})
    return result

@router.get("/patients", response_model=List[DoctorPatientOut])
def list_authorized_patients(
    priority: Optional[str] = None,
    current_doctor: User = Depends(require_role(["doctor"])),
    db: Session = Depends(get_db)
):
    # Retrieve all active links for this doctor
    access_links = db.query(DoctorPatientAccess).filter(
        DoctorPatientAccess.doctor_id == current_doctor.id,
        DoctorPatientAccess.status == "active",
        DoctorPatientAccess.expires_at > datetime.now(timezone.utc)
    ).all()

    patient_ids = [link.patient_id for link in access_links]
    patients = db.query(User).filter(User.id.in_(patient_ids), User.role == "patient").all()

    results = []
    for p in patients:
        authorize(db, current_doctor, p.id)
        review = review_status(db, p)
        last_checkin = db.query(CheckIn).filter(CheckIn.user_id == p.id).order_by(CheckIn.created_at.desc()).first()
        active_exp = db.query(Experiment).filter(Experiment.user_id == p.id, Experiment.status == "active", Experiment.engine_version == 2).first()
        active_products_cnt = db.query(Product).filter(Product.user_id == p.id, Product.status == "active").count()
        notes = db.query(ClinicalNote).filter(ClinicalNote.patient_id == p.id).order_by(ClinicalNote.created_at.desc()).all()

        # List triage cannot be silently lowered by a note or clinician recommendation.
        p_priority = {"track": "routine", "low_risk_self_care": "routine", "doctor_review": "review", "urgent": "urgent"}[review["safety"]["status"]]
        if notes:
            p_priority = max((p_priority, notes[0].priority), key=lambda value: {"routine": 0, "review": 1, "urgent": 2}[value])

        if priority and p_priority != priority:
            continue

        results.append(DoctorPatientOut(
            patient_id=p.id,
            safety=review["safety"],
            review_state=review["state"],
            access=[access_out(g, db) for g in access_links if g.patient_id == p.id],
            full_name=p.full_name,
            email=p.email,
            skin_type=p.skin_type,
            selected_goal=p.selected_goal,
            last_check_in=last_checkin.date_str if last_checkin else "No check-ins yet",
            active_experiment="active" if active_exp else None,
            priority=p_priority,
            active_products_count=active_products_cnt,
            notes=[ClinicalNoteOut.model_validate(n) for n in notes]
        ))
    return results

@router.post("/patients/{patient_id}/notes", response_model=ClinicalNoteOut, status_code=status.HTTP_201_CREATED)
def add_clinical_note(
    patient_id: str,
    payload: ClinicalNoteCreate,
    current_doctor: User = Depends(require_role(["doctor"])),
    db: Session = Depends(get_db),
    response: Response = None,
    idempotency_key: list[str] | None = Header(None),
    original_grant_id: str | None = Header(None, alias="Original-Grant-Id", min_length=1, max_length=36),
):
    response = response or Response()
    idempotency_key = clinical_attempts.key(idempotency_key)
    patient, grant = authorize(db, current_doctor, patient_id, access_id=original_grant_id)
    response.headers['Original-Grant-Binding'] = 'explicit' if original_grant_id else 'legacy-current'
    attempt, previous = clinical_attempts.begin(db, current_doctor.id, patient_id, grant, 'note', idempotency_key, payload, response)
    if previous is not None:
        return previous
    if payload.review_action_id and not db.query(DoctorReviewAction).filter_by(
            id=payload.review_action_id, patient_id=patient_id).first():
        raise HTTPException(422, "Review linkage is not a record for this patient")
    if payload.timeline_item_id and payload.timeline_item_id not in {i["id"] for i in timeline(db, patient)["items"]}:
        raise HTTPException(422, "Timeline linkage is not an available item for this patient")
    now = datetime.now(timezone.utc)
    note = ClinicalNote(
        id=gen_uuid(),
        doctor_id=current_doctor.id,
        patient_id=patient_id,
        content=payload.content,
        priority=payload.priority,
        follow_up=payload.follow_up,
        category=payload.category,
        patient_visible=payload.patient_visible,
        timeline_item_id=payload.timeline_item_id,
        review_action_id=payload.review_action_id,
        created_at=now,
        updated_at=now,
    )
    db.add(note)
    clinical_attempts.stage(db, attempt, note.id, ClinicalNoteOut.model_validate(note).model_dump(mode="json"), response)
    save(db, current_doctor.id, "CLINICAL_NOTE_ADDED", "clinical_notes", {
        "note_id": note.id,
        "patient_id": patient_id,
        "priority": payload.priority
    })

    return note


@router.get("/access", response_model=list[AccessGrantOut])
def patient_access(current_user: User = Depends(require_role(["patient"])), db: Session = Depends(get_db)):
    return [access_out(g, db) for g in db.query(DoctorPatientAccess).filter_by(patient_id=current_user.id).order_by(DoctorPatientAccess.created_at, DoctorPatientAccess.id)]


@router.delete("/access/{access_id}", response_model=AccessGrantOut)
def revoke_one(access_id: str, current_user: User = Depends(require_role(["patient"])), db: Session = Depends(get_db),
        response: Response = None, idempotency_key: list[str] | None = Header(None)):
    response = response or Response()
    attempt, previous = grant_attempts.begin(db, current_user.id, 'revoke', idempotency_key,
        {"access_id": access_id}, response)
    if previous is not None:
        return previous
    grant = db.query(DoctorPatientAccess).filter_by(id=access_id, patient_id=current_user.id).with_for_update().first()
    if not grant:
        raise HTTPException(404, "Access grant not found")
    changed = grant.status != "revoked"
    if changed:
        grant.status = "revoked"
        grant.revoked_at = datetime.now(timezone.utc)
        grant.revoked_by = current_user.id
    flush_clinical(db)
    result = access_out(grant, db)
    grant_attempts.stage(db, attempt, grant.id, result, response)
    if changed:
        save(db, current_user.id, "PATIENT_ACCESS_REVOKED", "doctor_patient_access", {"patient_id": current_user.id, "access_id": grant.id})
    elif attempt is not None:
        save(db, current_user.id, "CONSENT_REVOCATION_RECONCILED", "doctor_patient_access",
            {"patient_id": current_user.id, "access_id": grant.id, "attempt_id": attempt.id})
    return result


@router.get("/review-status", response_model=ReviewStatusOut)
def patient_review_status(current_user: User = Depends(require_role(["patient"])), db: Session = Depends(get_db)):
    return review_status(db, current_user, patient_view=True)


@router.get("/patients/{patient_id}", response_model=DoctorPatientDetailOut)
def patient_detail(patient_id: str, current_doctor: User = Depends(require_role(["doctor"])), db: Session = Depends(get_db)):
    patient, grant = authorize(db, current_doctor, patient_id)
    return {"patient_id": patient.id, "full_name": patient.full_name, "access": access_out(grant, db),
        "review": review_status(db, patient)}


@router.get("/patients/{patient_id}/timeline", response_model=DoctorTimelineOut)
def patient_timeline(patient_id: str, offset: int = Query(0, ge=0), limit: int = Query(100, ge=1, le=200),
        current_doctor: User = Depends(require_role(["doctor"])), db: Session = Depends(get_db)):
    patient, _ = authorize(db, current_doctor, patient_id)
    result = timeline(db, patient)
    count = len(result["items"])
    result.update(total=count, offset=offset, limit=limit, next_offset=offset+limit if offset+limit < count else None)
    result["items"] = result["items"][offset:offset+limit]
    return result


@router.get("/patients/{patient_id}/notes", response_model=List[ClinicalNoteOut])
def patient_notes(patient_id: str, current_doctor: User = Depends(require_role(["doctor"])), db: Session = Depends(get_db)):
    authorize(db, current_doctor, patient_id)
    return db.query(ClinicalNote).filter_by(patient_id=patient_id).order_by(ClinicalNote.created_at, ClinicalNote.id).all()


@router.get("/patients/{patient_id}/reviews", response_model=ReviewStatusOut)
def patient_reviews(patient_id: str, current_doctor: User = Depends(require_role(["doctor"])), db: Session = Depends(get_db)):
    patient, _ = authorize(db, current_doctor, patient_id)
    return review_status(db, patient)


@router.post("/patients/{patient_id}/reviews", response_model=ReviewActionOut, status_code=201)
def add_review(patient_id: str, payload: ReviewActionCreate,
        current_doctor: User = Depends(require_role(["doctor"])), db: Session = Depends(get_db),
        response: Response = None, idempotency_key: list[str] | None = Header(None),
        original_grant_id: str | None = Header(None, alias="Original-Grant-Id", min_length=1, max_length=36)):
    response = response or Response()
    idempotency_key = clinical_attempts.key(idempotency_key)
    patient, grant = authorize(db, current_doctor, patient_id, access_id=original_grant_id)
    response.headers['Original-Grant-Binding'] = 'explicit' if original_grant_id else 'legacy-current'
    attempt, previous = clinical_attempts.begin(db, current_doctor.id, patient_id, grant, 'review', idempotency_key, payload, response)
    if previous is not None:
        return previous
    history = reviews(db, patient_id)
    sequence = history[0].sequence if history else 0
    if payload.expected_sequence != sequence:
        raise HTTPException(409, "Review changed; refresh before recording another action")
    safety = evaluate_safety(db, patient)
    row = DoctorReviewAction(patient_id=patient_id, doctor_id=current_doctor.id, access_id=grant.id,
        sequence=sequence+1, state=payload.state, recommendation=payload.recommendation,
        rationale=payload.rationale, patient_visible=payload.patient_visible,
        safety_snapshot=safety.model_dump(mode="json"))
    db.add(row)
    flush_clinical(db)
    clinical_attempts.stage(db, attempt, row.id, ReviewActionOut.model_validate(review_out(row, safety, current_sequence=row.sequence)).model_dump(mode="json"), response)
    save(db, current_doctor.id, "DOCTOR_REVIEW_RECORDED", "doctor_review_actions",
        {"patient_id": patient_id, "sequence": sequence+1, "state": payload.state})
    return review_out(row, safety, current_sequence=row.sequence)


@router.get("/patients/{patient_id}/attempts/{operation}/{key}")
def clinical_attempt_readback(patient_id: str, operation: str, key: str, response: Response,
        current_doctor: User = Depends(require_role(["doctor"])), db: Session = Depends(get_db)):
    _, grant = authorize(db, current_doctor, patient_id)
    identifier = clinical_attempts.identity(current_doctor.id, patient_id, operation, key)
    from app.models.clinical_attempts import ClinicalAttempt
    row = db.get(ClinicalAttempt, identifier)
    response.headers["Cache-Control"] = "no-store"
    if row and row.access_id != grant.id:
        raise HTTPException(409, "Attempt belongs to a different consent grant")
    return clinical_attempts.out(row) if row else {"schema_version": 1, "attempt_id": identifier,
        "status": "unknown", "result": None, "retry_safe": False}


@router.get("/consent-attempts/{operation}/{key}")
def consent_attempt_readback(operation: str, key: str, response: Response,
        current_user: User = Depends(require_role(["patient"])), db: Session = Depends(get_db)):
    from app.models import GrantAttempt
    identifier = grant_attempts.identity(current_user.id, operation, key)
    row = db.get(GrantAttempt, identifier)
    response.headers["Cache-Control"] = "no-store"
    return grant_attempts.out(db, row) if row else {"schema_version": 1,
        "attempt_id": identifier, "status": "unknown", "result": None, "retry_safe": False}
