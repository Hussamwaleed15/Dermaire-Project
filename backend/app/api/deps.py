from typing import List, Optional
from fastapi import Depends, Header, status
from sqlalchemy.orm import Session
import jwt
from app.core.database import get_db
from app.core.config import settings
from app.core.exceptions import InvalidCredentialsException, PermissionDeniedException
from app.models import User, AuditLog

def get_token_subject(authorization: Optional[str] = Header(None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise InvalidCredentialsException("Authorization header missing or invalid format")
    try:
        payload = jwt.decode(authorization[7:], settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("type") != "access" or not isinstance(payload.get("sub"), str):
            raise InvalidCredentialsException("Invalid access token")
        return payload["sub"]
    except jwt.PyJWTError:
        raise InvalidCredentialsException("Token is expired or invalid")


def get_current_user(
    authorization: Optional[str] = Header(None),
    db: Session = Depends(get_db)
) -> User:
    user_id = get_token_subject(authorization)

    user = db.query(User).filter(User.id == user_id).with_for_update().first()
    if not user:
        raise InvalidCredentialsException("User no longer exists")
    return user

def require_role(allowed_roles: List[str]):
    def role_checker(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role not in allowed_roles:
            raise PermissionDeniedException(
                f"User role '{current_user.role}' is not authorized. Required: {allowed_roles}"
            )
        return current_user
    return role_checker

def record_audit(db: Session, actor_id: str, action: str, target: str, details: dict, ip_address: Optional[str] = None):
    audit = AuditLog(
        actor_id=actor_id,
        action=action,
        target_resource=target,
        details=details,
        ip_address=ip_address
    )
    db.add(audit)
    db.commit()
