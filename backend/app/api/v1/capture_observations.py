import json
from uuid import uuid5, NAMESPACE_URL
from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User, Capture, CheckIn, CaptureObservation, AuditLog
from app.schemas.capture_observations import CaptureObservationSelect, CaptureObservationOut
from app.services.routine import lock_owner, commit
from app.services.personal_skin_model import report_of
from app.services.doctor_loop import authorize
from app.services.temporal import utc

router = APIRouter(prefix='/captures', tags=['Capture observation references'])


def projection(row):
    return CaptureObservationOut(id=row.id, capture_id=row.capture_id, checkin_id=row.checkin_id, created_at=utc(row.created_at))


def owned_pair(db, user, capture_id, checkin_id):
    if user.role != 'patient':
        raise HTTPException(403, 'Only the patient can select observation associations')
    lock_owner(db, user)
    capture = db.query(Capture).filter_by(id=capture_id, user_id=user.id).first()
    check = db.query(CheckIn).filter_by(id=checkin_id, user_id=user.id).first()
    if not capture or not check:
        raise HTTPException(404, 'Capture or observation not found')
    if capture.state != 'accepted' or report_of(check) is None:
        raise HTTPException(422, 'Accepted capture and a structured user observation are required')


@router.put('/{capture_id}/observations/{checkin_id}', response_model=CaptureObservationOut)
def select(capture_id: str, checkin_id: str, payload: CaptureObservationSelect,
           user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    owned_pair(db, user, capture_id, checkin_id)
    identifier = str(uuid5(NAMESPACE_URL, json.dumps(['capture-observation-1', user.id, capture_id, checkin_id])))
    row = db.query(CaptureObservation).filter_by(id=identifier, user_id=user.id).first()
    if row is None:
        row = CaptureObservation(id=identifier, user_id=user.id, capture_id=capture_id, checkin_id=checkin_id)
        db.add(row)
        db.add(AuditLog(actor_id=user.id, action='CAPTURE_OBSERVATION_SELECTED', target_resource='capture_observations', details={'association_id': identifier}))
        commit(db)
        db.refresh(row)
    return projection(row)


@router.delete('/{capture_id}/observations/{checkin_id}', status_code=204)
def unselect(capture_id: str, checkin_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    owned_pair(db, user, capture_id, checkin_id)
    row = db.query(CaptureObservation).filter_by(user_id=user.id, capture_id=capture_id, checkin_id=checkin_id).first()
    if row:
        db.add(AuditLog(actor_id=user.id, action='CAPTURE_OBSERVATION_REMOVED', target_resource='capture_observations', details={'association_id': row.id}))
        db.delete(row)
        commit(db)
    return Response(status_code=204)


@router.get('/{capture_id}/observations', response_model=list[CaptureObservationOut])
def associations(capture_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    capture = db.query(Capture).filter_by(id=capture_id).first()
    if capture is None:
        raise HTTPException(404, 'Capture not found')
    if capture.user_id != user.id:
        if user.role != 'doctor':
            raise HTTPException(404, 'Capture not found')
        authorize(db, user, capture.user_id, scope='VIEW')
    # Recheck linked ownership even for inconsistent legacy/imported rows.
    rows = db.query(CaptureObservation).join(CheckIn, CheckIn.id == CaptureObservation.checkin_id).filter(
        CaptureObservation.user_id == capture.user_id, CaptureObservation.capture_id == capture.id,
        CheckIn.user_id == capture.user_id).order_by(CaptureObservation.created_at, CaptureObservation.id).all()
    return [projection(row) for row in rows]
