from datetime import datetime, timedelta, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status, HTTPException
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.security import create_doctor_access_token, decode_token
from app.core.exceptions import (
    PermissionDeniedException, DermaireException
)
from app.api.deps import require_role
from app.models import User, DoctorPatientAccess, ClinicalNote, CheckIn, Experiment, Product, DoctorReviewAction, gen_uuid
from app.services.doctor_loop import authorize, save, access_out, timeline, review_status, reviews, review_out
from app.schemas.doctor_loop import ReviewActionCreate
from app.services.safety import evaluate_safety
from app.schemas import (
    GenerateQrResponse, ClaimAccessRequest, DoctorPatientOut,
    ClinicalNoteCreate, ClinicalNoteOut
)

router = APIRouter(prefix="/doctor", tags=["Doctor Portal, QR Access & Audit"])

@router.post("/generate-qr", response_model=GenerateQrResponse)
def generate_doctor_qr_access(
    minutes_valid: int = Query(60, ge=15, le=1440),
    current_user: User = Depends(require_role(["patient"])),
    db: Session = Depends(get_db)
):
    token = create_doctor_access_token(current_user.id, minutes_valid=minutes_valid)
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=minutes_valid)

    access_record = DoctorPatientAccess(
        id=gen_uuid(),
        patient_id=current_user.id,
        access_token=token,
        status="pending",
        export_consent=True,
        granted_by=current_user.id,
        expires_at=expires_at
    )
    db.add(access_record)
    save(db, current_user.id, "DOCTOR_QR_GENERATED", "doctor_patient_access", {
        "access_id": access_record.id,
        "expires_at": expires_at.isoformat(),
        "patient_id": current_user.id
    })

    return GenerateQrResponse(
        access_token=token,
        qr_payload=f"dermaire://doctor-access?token={token}",
        expires_at=expires_at,
        instructions="Present this QR code to your clinician. Access is temporary, encrypted, and can be revoked at any moment."
    )

@router.post("/claim", status_code=status.HTTP_200_OK)
def claim_patient_access(
    payload: ClaimAccessRequest,
    current_doctor: User = Depends(require_role(["doctor"])),
    db: Session = Depends(get_db)
):
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

    access_record.doctor_id = current_doctor.id
    access_record.status = "active"
    access_record.claimed_at = access_record.claimed_at or datetime.now(timezone.utc)
    save(db, current_doctor.id, "PATIENT_ACCESS_CLAIMED", "doctor_patient_access", {
        "patient_id": patient_id,
        "doctor_id": current_doctor.id,
        "access_id": access_record.id
    })
    return {"success": True, "message": f"Access granted to patient record ({patient_id})."}

@router.delete("/revoke/{patient_id}", status_code=status.HTTP_200_OK)
def revoke_patient_access(
    patient_id: str,
    current_user: User = Depends(require_role(["patient"])),
    db: Session = Depends(get_db)
):
    # Patient can revoke their own access
    if current_user.id != patient_id:
        raise PermissionDeniedException("You can only revoke access for your own patient records.")

    records = db.query(DoctorPatientAccess).filter(
        DoctorPatientAccess.patient_id == patient_id,
        DoctorPatientAccess.status.in_(["active", "pending"])
    ).with_for_update().all()
    for r in records:
        r.status = "revoked"
        r.revoked_at = datetime.now(timezone.utc)
        r.revoked_by = current_user.id
    save(db, current_user.id, "PATIENT_ACCESS_REVOKED", "doctor_patient_access", {"patient_id": patient_id, "access_ids": [r.id for r in records]})
    return {"success": True, "message": "Clinician access revoked immediately."}

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
            access=[access_out(g) for g in access_links if g.patient_id == p.id],
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
    db: Session = Depends(get_db)
):
    patient, grant = authorize(db, current_doctor, patient_id)
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
    save(db, current_doctor.id, "CLINICAL_NOTE_ADDED", "clinical_notes", {
        "note_id": note.id,
        "patient_id": patient_id,
        "priority": payload.priority
    })

    return note


@router.get("/access")
def patient_access(current_user: User = Depends(require_role(["patient"])), db: Session = Depends(get_db)):
    return [access_out(g) for g in db.query(DoctorPatientAccess).filter_by(patient_id=current_user.id).order_by(DoctorPatientAccess.created_at, DoctorPatientAccess.id)]


@router.delete("/access/{access_id}")
def revoke_one(access_id: str, current_user: User = Depends(require_role(["patient"])), db: Session = Depends(get_db)):
    grant = db.query(DoctorPatientAccess).filter_by(id=access_id, patient_id=current_user.id).with_for_update().first()
    if not grant:
        raise HTTPException(404, "Access grant not found")
    if grant.status != "revoked":
        grant.status = "revoked"
        grant.revoked_at = datetime.now(timezone.utc)
        grant.revoked_by = current_user.id
        save(db, current_user.id, "PATIENT_ACCESS_REVOKED", "doctor_patient_access", {"patient_id": current_user.id, "access_id": grant.id})
    return access_out(grant)


@router.get("/review-status")
def patient_review_status(current_user: User = Depends(require_role(["patient"])), db: Session = Depends(get_db)):
    return review_status(db, current_user, patient_view=True)


@router.get("/patients/{patient_id}")
def patient_detail(patient_id: str, current_doctor: User = Depends(require_role(["doctor"])), db: Session = Depends(get_db)):
    patient, grant = authorize(db, current_doctor, patient_id)
    return {"patient_id": patient.id, "full_name": patient.full_name, "access": access_out(grant),
        "review": review_status(db, patient)}


@router.get("/patients/{patient_id}/timeline")
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


@router.get("/patients/{patient_id}/reviews")
def patient_reviews(patient_id: str, current_doctor: User = Depends(require_role(["doctor"])), db: Session = Depends(get_db)):
    patient, _ = authorize(db, current_doctor, patient_id)
    return review_status(db, patient)


@router.post("/patients/{patient_id}/reviews", status_code=201)
def add_review(patient_id: str, payload: ReviewActionCreate,
        current_doctor: User = Depends(require_role(["doctor"])), db: Session = Depends(get_db)):
    patient, grant = authorize(db, current_doctor, patient_id)
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
    save(db, current_doctor.id, "DOCTOR_REVIEW_RECORDED", "doctor_review_actions",
        {"patient_id": patient_id, "sequence": sequence+1, "state": payload.state})
    return review_out(row, safety)
