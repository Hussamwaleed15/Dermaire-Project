from typing import List, Optional
from fastapi import Depends, Header, Request, HTTPException
from sqlalchemy.orm import Session
import jwt
import secrets
from app.core.security import credential_stamp
from app.core.database import get_db
from app.core.config import settings
from app.core.exceptions import InvalidCredentialsException, PermissionDeniedException
from app.models import User, AuditLog

def get_token_payload(authorization: Optional[str] = Header(None)) -> dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise InvalidCredentialsException("Authorization header missing or invalid format")
    try:
        payload = jwt.decode(
            authorization[7:], settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
            options={"require": ["exp", "iat", "sub", "jti", "credential"]},
        )
        if payload.get("type") != "access" or not isinstance(payload.get("sub"), str):
            raise InvalidCredentialsException("Invalid access token")
        if not all(isinstance(payload.get(key), str) and payload[key] for key in ("sub", "jti", "credential")):
            raise InvalidCredentialsException("Invalid access token")
        credential = payload["credential"]
        if len(credential) != 64 or any(c not in "0123456789abcdef" for c in credential):
            raise InvalidCredentialsException("Invalid access token")
        return payload
    except (jwt.PyJWTError, TypeError, ValueError):
        raise InvalidCredentialsException("Token is expired or invalid")


def get_token_subject(payload: dict = Depends(get_token_payload), db: Session = Depends(get_db)) -> str:
    return validate_token_subject(payload, db, lock=True)


def validate_token_subject(payload: dict, db: Session, *, lock: bool):
    query = db.query(User).filter(User.id == payload["sub"])
    user = (query.with_for_update() if lock else query).first()
    if user and not secrets.compare_digest(payload["credential"], credential_stamp(user.hashed_password)):
        raise InvalidCredentialsException("Session invalidated. Please sign in again")
    revoked = db.query(AuditLog).filter(
        AuditLog.actor_id == payload["sub"],
        AuditLog.action == "SESSION_REVOKED",
        AuditLog.target_resource == payload["jti"],
    ).first()
    if revoked:
        raise InvalidCredentialsException("Session has been logged out")
    return payload["sub"]


def get_current_user(
    request: Request,
    user_id: str = Depends(get_token_subject),
    db: Session = Depends(get_db)
) -> User:

    user = db.query(User).filter(User.id == user_id).with_for_update().first()
    if not user:
        raise InvalidCredentialsException("User no longer exists")
    if settings.SAFETY_POLICY_ENFORCE and request.method in ("POST", "PATCH", "PUT", "DELETE"):
        path = request.url.path
        recovery = path in (settings.API_V1_STR + "/auth/accept-safety", settings.API_V1_STR + "/auth/logout", settings.API_V1_STR + "/users/me") or path.startswith(settings.API_V1_STR + "/doctor/access/") or path.startswith(settings.API_V1_STR + "/doctor/revoke/")
        recovery = recovery or (request.method == "DELETE" and path.startswith(settings.API_V1_STR + "/messaging/threads/") and path.endswith("/consent"))
        if not recovery and user.safety_consent["acceptance_required"]:
            raise HTTPException(403, "Current safety policy acceptance required; read /users/me")
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
