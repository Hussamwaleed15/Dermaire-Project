from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Query, Response, HTTPException
from sqlalchemy.orm import Session
from app.api.deps import get_current_user, get_token_payload
from app.core.database import get_db
from app.models import User
from app.models.notifications import Notification, NotificationDevice, NotificationJob
from app.schemas.notifications import PreferencesIn, DeviceIn
from app.services import notifications as service
from app.services.temporal import utc

router=APIRouter(prefix="/notifications",tags=["Notification inbox"])


@router.get("/preferences")
def preferences(response: Response, actor: User=Depends(get_current_user), db: Session=Depends(get_db)):
    response.headers["Cache-Control"]="no-store"
    return service.preference_out(service.preferences(db,actor.id))


@router.put("/preferences")
def change_preferences(payload: PreferencesIn,response: Response,actor: User=Depends(get_current_user),db: Session=Depends(get_db)):
    response.headers["Cache-Control"]="no-store"
    return service.change_preferences(db,actor,payload)


@router.post("/devices",status_code=201)
def register(payload: DeviceIn,response: Response,actor: User=Depends(get_current_user),
             claims: dict=Depends(get_token_payload),db: Session=Depends(get_db)):
    response.headers["Cache-Control"]="no-store"
    return service.register(db,actor,claims,payload)


@router.delete("/preferences")
def disable(response: Response,expected_revision: int=Query(ge=0),
            actor: User=Depends(get_current_user),db: Session=Depends(get_db)):
    response.headers["Cache-Control"]="no-store"
    current=service.preference_out(service.preferences(db,actor.id))
    payload=PreferencesIn(expected_revision=expected_revision,enabled_kinds=[],push_enabled=False,
        timezone=current["timezone"],quiet_start=current["quiet_start"],quiet_end=current["quiet_end"])
    return service.change_preferences(db,actor,payload)


@router.delete("/devices/{device_id}")
def revoke(device_id: str,response: Response,actor: User=Depends(get_current_user),db: Session=Depends(get_db)):
    response.headers["Cache-Control"]="no-store"
    row=db.query(NotificationDevice).filter_by(id=device_id,user_id=actor.id).with_for_update().first()
    if not row: raise HTTPException(404,"Device not found")
    row.revoked_at=datetime.now(timezone.utc); row.token_encrypted=""
    db.query(NotificationJob).filter(NotificationJob.device_id==row.id,NotificationJob.state!="provider_accepted").update(
        {"state":"cancelled","lease_token":None,"lease_until":None},synchronize_session=False)
    db.commit()
    return {"id":row.id,"status":"revoked"}


@router.get("")
def inbox(response: Response,limit: int=Query(50,ge=1,le=100),before: str | None=None,
          actor: User=Depends(get_current_user),db: Session=Depends(get_db)):
    response.headers["Cache-Control"]="no-store"
    now=datetime.now(timezone.utc)
    query=db.query(Notification).filter(Notification.user_id==actor.id,Notification.due_at<=now,Notification.cancelled_at.is_(None))
    if before:
        anchor=db.query(Notification).filter_by(id=before,user_id=actor.id).first()
        if not anchor: raise HTTPException(422,"Invalid inbox cursor")
        from sqlalchemy import or_, and_
        query=query.filter(or_(Notification.created_at<anchor.created_at,
            and_(Notification.created_at==anchor.created_at,Notification.id<anchor.id)))
    # Private message references must remain authorized after a grant is revoked.
    rows=query.order_by(Notification.created_at.desc(),Notification.id.desc()).limit(limit+1).all()
    items=[{"id":row.id,"kind":row.kind,"source_id":row.source_id,"source_revision":row.source_revision,
            "created_at":utc(row.created_at),"due_at":utc(row.due_at),"read_at":utc(row.read_at) if row.read_at else None,
            "unread":row.read_at is None,"state_revision":row.state_revision,
            "target":service.target(db,row,now),"push_delivery":"unconfirmed"} for row in rows[:limit] if service.source_active(db,row,now)]
    return {"items":items,"next_before":rows[limit-1].id if len(rows)>limit else None,
            "unread_in_page":sum(item["unread"] for item in items),
            "provider":"disabled","delivery_confirmed":False}


@router.put("/{notification_id}/read")
def read(notification_id: str,response: Response,expected_revision: int | None=Query(None,ge=1),
         actor: User=Depends(get_current_user),db: Session=Depends(get_db)):
    response.headers["Cache-Control"]="no-store"
    row=db.query(Notification).filter_by(id=notification_id,user_id=actor.id).with_for_update().first()
    now=datetime.now(timezone.utc)
    if not row or row.cancelled_at or utc(row.due_at)>now or not service.source_active(db,row,now):
        raise HTTPException(404,"Notification not found")
    if expected_revision is not None and row.state_revision!=expected_revision:
        raise HTTPException(412,"Notification state changed; refresh revision")
    if not row.read_at: row.read_at=now; row.state_revision+=1; db.commit()
    return {"id":row.id,"read_at":utc(row.read_at),"unread":False,"state_revision":row.state_revision,
        "receipt":"app_read_acknowledged","delivery_confirmed":False}

@router.get("/routine-reminders/{entry_id}")
def get_routine_reminder(entry_id: str,response: Response,actor: User=Depends(get_current_user),db: Session=Depends(get_db)):
    from app.services import routine_reminders
    from app.models.notifications import RoutineReminderSetting
    response.headers["Cache-Control"]="no-store"
    routine_reminders.owned_entry(db,actor.id,entry_id)
    return routine_reminders.output(db.query(RoutineReminderSetting).filter_by(routine_entry_id=entry_id).first())


from app.schemas.notifications import RoutineReminderIn

@router.put("/routine-reminders/{entry_id}")
def put_routine_reminder(entry_id: str,payload: RoutineReminderIn,response: Response,
                         actor: User=Depends(get_current_user),db: Session=Depends(get_db)):
    from app.services import routine_reminders
    response.headers["Cache-Control"]="no-store"
    return routine_reminders.configure(db,actor,entry_id,payload)


@router.put("/{notification_id}/unread")
def unread(notification_id: str,response: Response,expected_revision: int | None=Query(None,ge=1),
           actor: User=Depends(get_current_user),db: Session=Depends(get_db)):
    response.headers["Cache-Control"]="no-store"
    row=db.query(Notification).filter_by(id=notification_id,user_id=actor.id).with_for_update().first()
    now=datetime.now(timezone.utc)
    if not row or row.cancelled_at or utc(row.due_at)>now or not service.source_active(db,row,now):
        raise HTTPException(404,"Notification not found")
    if expected_revision is not None and row.state_revision!=expected_revision:
        raise HTTPException(412,"Notification state changed; refresh revision")
    if row.read_at is not None:row.read_at=None;row.state_revision+=1;db.commit()
    return {"id":row.id,"read_at":None,"unread":True,"state_revision":row.state_revision,"delivery_confirmed":False}

@router.get("/history")
def history(response: Response,limit: int=Query(50,ge=1,le=100),before: str | None=None,
            actor: User=Depends(get_current_user),db: Session=Depends(get_db)):
    """Privacy-filtered bounded state readback; no promise of transport attempt history."""
    response.headers["Cache-Control"]="no-store"
    query=db.query(Notification).filter_by(user_id=actor.id)
    if before:
        anchor=query.filter(Notification.id==before).first()
        if not anchor:raise HTTPException(422,"Invalid notification history cursor")
        from sqlalchemy import or_,and_
        query=query.filter(or_(Notification.created_at<anchor.created_at,
            and_(Notification.created_at==anchor.created_at,Notification.id<anchor.id)))
    rows=query.order_by(Notification.created_at.desc(),Notification.id.desc()).limit(limit+1).all()
    now=datetime.now(timezone.utc)
    items=[]
    from app.models import RoutineEntry
    for row in rows[:limit]:
        active=service.source_active(db,row,now)
        owned_routine=row.kind=="routine" and db.query(RoutineEntry).filter_by(id=row.source_id,user_id=actor.id).first() is not None
        if not active and not owned_routine:continue
        jobs=db.query(NotificationJob).filter_by(notification_id=row.id).all()
        items.append({"id":row.id,"kind":row.kind,"due_at":utc(row.due_at),
            "state":"cancelled" if row.cancelled_at or not active else "current",
            "cancelled_at":utc(row.cancelled_at) if row.cancelled_at else None,
            "jobs":[{"id":job.id,"state":job.state,"attempts":job.attempts,
                     "attempt_history":service.attempt_history(db,job,now)} for job in jobs],
            "delivery_confirmed":False})
    return {"items":items,"next_before":rows[limit-1].id if len(rows)>limit else None,
            "history_contract":"prospective_attempts_and_current_authority_no_delivery_proof"}
