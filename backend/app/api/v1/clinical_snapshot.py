"""Separate transaction boundary; ordinary endpoints retain existing contracts."""
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError
from app.core.database import engine
from app.api.deps import get_token_payload, get_token_subject, get_current_user, validate_token_subject
from app.core.exceptions import InvalidCredentialsException, PermissionDeniedException
from app.models import User
from app.schemas.clinical_snapshot import ClinicalSnapshotOut
from app.services.clinical_snapshot import build_snapshot

router=APIRouter(prefix='/clinical-snapshot', tags=['Clinical Snapshot'])


def snapshot_db():
    if engine.dialect.name != 'postgresql':
        raise HTTPException(503, 'Consistent clinical bundle requires PostgreSQL repeatable read')
    try:
        with engine.connect().execution_options(isolation_level='REPEATABLE READ') as connection:
            with Session(bind=connection, autoflush=False) as db:
                yield db
    except SQLAlchemyError:
        raise HTTPException(503, 'Clinical snapshot unavailable; read a new snapshot') from None


@router.get('',response_model=ClinicalSnapshotOut)
def clinical_snapshot(request: Request, response: Response,
    payload: dict = Depends(get_token_payload), db: Session = Depends(snapshot_db)):
    subject=get_token_subject(payload,db)
    user=get_current_user(request,subject,db)
    if user.role != 'patient':
        raise PermissionDeniedException('Clinical bundle is available to its patient owner only')
    result=build_snapshot(db,user)
    # Repeatable-read can wait behind a logout that only inserts an audit row.
    # Recheck current auth outside MVCC before releasing any clinical content.
    # Plain reads avoid blocking on our own owner lock; the owner lock stays held.
    payload=get_token_payload(request.headers.get('authorization'))
    with engine.connect().execution_options(isolation_level='READ COMMITTED') as current:
        with Session(bind=current) as auth_db:
            current_subject=validate_token_subject(payload,auth_db,lock=False)
            current_user=auth_db.get(User,current_subject)
            if current_user is None:
                raise InvalidCredentialsException('User no longer exists')
            if current_user.role != 'patient':
                raise PermissionDeniedException('Clinical bundle is available to its patient owner only')
    response.headers['Cache-Control']='no-store'
    response.headers['Pragma']='no-cache'
    return result
