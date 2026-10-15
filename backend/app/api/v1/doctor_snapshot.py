from datetime import datetime,timezone
from fastapi import APIRouter,Depends,HTTPException,Request,Response
from sqlalchemy.orm import Session
from app.api.deps import get_token_payload,get_token_subject,get_current_user,validate_token_subject
from app.api.v1 import clinical_snapshot as patient_api
from app.core.exceptions import InvalidCredentialsException,PermissionDeniedException
from app.models import User,DoctorPatientAccess
from app.schemas.doctor_snapshot import DoctorClinicalSnapshotOut
from app.services.doctor_consent import granted_scopes
from app.services.doctor_loop import authorize
from app.services.doctor_snapshot import build_doctor_snapshot

router=APIRouter(prefix="/clinical-snapshot",tags=["Doctor clinical snapshot"])


@router.get("/patients/{patient_id}",response_model=DoctorClinicalSnapshotOut)
def doctor_snapshot(patient_id: str,request: Request,response: Response,
                    payload: dict=Depends(get_token_payload),db: Session=Depends(patient_api.snapshot_db)):
    subject=get_token_subject(payload,db)
    doctor=get_current_user(request,subject,db)
    if doctor.role!="doctor":raise PermissionDeniedException("Doctor role required")
    patient,grant=authorize(db,doctor,patient_id)
    result=build_doctor_snapshot(db,patient,doctor,grant)
    # Recheck current identity and original grant outside the snapshot before
    # releasing private clinician review content. Original patient/grant locks
    # remain held until dependency teardown; no export is authorized here.
    payload=get_token_payload(request.headers.get("authorization"))
    with patient_api.engine.connect().execution_options(isolation_level="READ COMMITTED") as current:
        with Session(bind=current) as gate:
            actor_id=validate_token_subject(payload,gate,lock=False)
            actor=gate.get(User,actor_id)
            if not actor:raise InvalidCredentialsException("User no longer exists")
            if actor.role!="doctor":raise PermissionDeniedException("Doctor role required")
            owner=gate.query(User).filter_by(id=patient_id,role="patient").first()
            access=gate.query(DoctorPatientAccess).filter_by(id=grant.id,patient_id=patient_id,doctor_id=actor_id,status="active").filter(
                DoctorPatientAccess.expires_at>datetime.now(timezone.utc)).first()
            if not owner or not access or "VIEW" not in granted_scopes(access):
                raise HTTPException(403,"No current access to this patient")
    response.headers["Cache-Control"]="no-store"
    response.headers["Pragma"]="no-cache"
    return result
