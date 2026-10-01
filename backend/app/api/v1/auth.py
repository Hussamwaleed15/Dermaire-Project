import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests
from azure.communication.email import EmailClient

from app.core.database import get_db
from app.core.security import get_password_hash, verify_password, create_access_token
from app.core.config import settings
from app.core.exceptions import DermaireException, InvalidCredentialsException
from app.models import User
from app.schemas import UserRegister, UserLogin, TokenResponse, UserOut, AcceptSafetyRequest
from app.api.deps import get_current_user, record_audit

router = APIRouter(prefix="/auth", tags=["Authentication & Medical Safety"])


class GoogleAuthRequest(BaseModel):
    id_token: str


class ForgotPasswordRequest(BaseModel):
    email: str


class ResetPasswordRequest(BaseModel):
    email: str
    token: str
    new_password: str


RESET_TOKEN_TTL_MINUTES = 30
MAX_RESET_ATTEMPTS = 5

def send_password_reset_email(recipient_email: str, reset_token: str):
    email_client = EmailClient.from_connection_string(
        settings.AZURE_COMMUNICATION_CONNECTION_STRING
    )

    message = {
        "senderAddress": settings.AZURE_EMAIL_SENDER,
        "recipients": {
            "to": [{"address": recipient_email}]
        },
        "content": {
            "subject": "Reset your Dermaire password",
            "plainText": (
                "You requested a password reset for your Dermaire account.\n\n"
                f"Your reset code is:\n{reset_token}\n\n"
                f"This code expires in {RESET_TOKEN_TTL_MINUTES} minutes.\n"
                "If you did not request this reset, you can ignore this email."
            ),
        },
    }

    poller = email_client.begin_send(message)
    poller.result()


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register_user(payload: UserRegister, db: Session = Depends(get_db)):
    if not payload.accept_safety:
        raise DermaireException(
            message="Medical responsibility acceptance is mandatory to use Dermaire personal skin lab.",
            error_code="SAFETY_ACCEPTANCE_REQUIRED",
            status_code=status.HTTP_400_BAD_REQUEST
        )

    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        raise DermaireException(
            message="An account with this email address already exists.",
            error_code="EMAIL_ALREADY_EXISTS",
            status_code=status.HTTP_409_CONFLICT
        )

    user = User(
        email=payload.email,
        hashed_password=get_password_hash(payload.password),
        full_name=payload.full_name,
        role="patient",
        safety_accepted=True,
        safety_accepted_at=datetime.now(timezone.utc),
        safety_policy_version="1.0",
        tokens_balance=6,
        baseline_checkins_count=2
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    record_audit(db, user.id, "USER_REGISTERED", "users", {"email": user.email, "role": user.role})

    token = create_access_token(subject=user.id, role=user.role)
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        user_id=user.id,
        role=user.role,
        full_name=user.full_name
    )


@router.post("/login", response_model=TokenResponse)
def login_user(payload: UserLogin, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if not user or not verify_password(payload.password, user.hashed_password):
        raise InvalidCredentialsException("Incorrect email or password. Please verify your credentials.")

    token = create_access_token(subject=user.id, role=user.role)
    record_audit(db, user.id, "USER_LOGGED_IN", "users", {"role": user.role})

    return TokenResponse(
        access_token=token,
        token_type="bearer",
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        user_id=user.id,
        role=user.role,
        full_name=user.full_name
    )


@router.post("/google", response_model=TokenResponse)
def google_login(payload: GoogleAuthRequest, db: Session = Depends(get_db)):
    """
    Verifies a real Google ID token (obtained on-device via the Flutter
    google_sign_in package with serverClientId = GOOGLE_WEB_CLIENT_ID) and
    signs the user in, creating an account automatically on first use.
    """
    try:
        info = google_id_token.verify_oauth2_token(
            payload.id_token,
            google_requests.Request(),
            audience=settings.GOOGLE_WEB_CLIENT_ID,
        )
    except ValueError:
        raise InvalidCredentialsException("Invalid or expired Google sign-in token.")

    if not info.get("email_verified", False):
        raise DermaireException(
            message="This Google account's email is not verified.",
            error_code="GOOGLE_EMAIL_NOT_VERIFIED",
            status_code=status.HTTP_400_BAD_REQUEST
        )

    email = info["email"]
    full_name = info.get("name") or email.split("@")[0].replace(".", " ").title()

    user = db.query(User).filter(User.email == email).first()
    is_new_user = user is None

    if is_new_user:
        # Google-authenticated accounts don't use a local password - store an
        # unusable random hash so the column constraint is still satisfied.
        user = User(
            email=email,
            hashed_password=get_password_hash(google_id_token.__name__ + email + str(datetime.now(timezone.utc))),
            full_name=full_name,
            role="patient",
            safety_accepted=False,
            tokens_balance=6,
            baseline_checkins_count=2
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        record_audit(db, user.id, "USER_REGISTERED_VIA_GOOGLE", "users", {"email": user.email})
    else:
        record_audit(db, user.id, "USER_LOGGED_IN_VIA_GOOGLE", "users", {"role": user.role})

    token = create_access_token(subject=user.id, role=user.role)
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        user_id=user.id,
        role=user.role,
        full_name=user.full_name
    )


@router.post("/forgot-password")
def forgot_password(payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """
    Starts the password-reset flow. If the account exists, an 8-digit
    single-use reset code is generated, only its SHA-256 hash is stored,
    and the code is delivered by email.

    The same generic response is returned whether or not the email exists,
    so this endpoint cannot be used to enumerate registered accounts.
    """
    user = db.query(User).filter(User.email == payload.email).first()

    reset_token = None
    if user:
        reset_token = f"{secrets.randbelow(100_000_000):08d}"
        user.reset_token_hash = hashlib.sha256(reset_token.encode()).hexdigest()
        user.reset_token_expires = datetime.now(timezone.utc) + timedelta(minutes=RESET_TOKEN_TTL_MINUTES)
        user.reset_token_attempts = 0
        db.commit()

        record_audit(db, user.id, "PASSWORD_RESET_REQUESTED", "users", {})
        send_password_reset_email(user.email, reset_token)

    response = {
        "message": "If an account exists for this email, a password reset code has been sent."
    }

    if settings.EXPOSE_PASSWORD_RESET_TOKEN and reset_token:
        response["reset_token"] = reset_token
        response["note"] = "Reset code exposure is enabled for testing only."

    return response


@router.post("/reset-password", response_model=UserOut)
def reset_password(payload: ResetPasswordRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()

    now = datetime.now(timezone.utc)
    expires_at = (
        user.reset_token_expires.replace(tzinfo=timezone.utc)
        if user and user.reset_token_expires
        else None
    )

    if not user or not user.reset_token_hash or not expires_at or expires_at < now:
        raise DermaireException(
            message="This reset code is invalid or has expired. Please request a new one.",
            error_code="RESET_TOKEN_INVALID",
            status_code=status.HTTP_400_BAD_REQUEST
        )

    if user.reset_token_attempts >= MAX_RESET_ATTEMPTS:
        user.reset_token_hash = None
        user.reset_token_expires = None
        user.reset_token_attempts = 0
        db.commit()
        raise DermaireException(
            message="Too many incorrect attempts. Please request a new reset code.",
            error_code="RESET_ATTEMPTS_EXCEEDED",
            status_code=status.HTTP_429_TOO_MANY_REQUESTS
        )

    token_hash = hashlib.sha256(payload.token.encode()).hexdigest()

    if not secrets.compare_digest(token_hash, user.reset_token_hash):
        user.reset_token_attempts += 1

        if user.reset_token_attempts >= MAX_RESET_ATTEMPTS:
            user.reset_token_hash = None
            user.reset_token_expires = None
            user.reset_token_attempts = 0
            db.commit()
            record_audit(db, user.id, "PASSWORD_RESET_ATTEMPTS_EXCEEDED", "users", {})
            raise DermaireException(
                message="Too many incorrect attempts. Please request a new reset code.",
                error_code="RESET_ATTEMPTS_EXCEEDED",
                status_code=status.HTTP_429_TOO_MANY_REQUESTS
            )

        db.commit()
        raise DermaireException(
            message="This reset code is invalid or has expired. Please try again.",
            error_code="RESET_TOKEN_INVALID",
            status_code=status.HTTP_400_BAD_REQUEST
        )

    user.hashed_password = get_password_hash(payload.new_password)
    user.reset_token_hash = None
    user.reset_token_expires = None
    user.reset_token_attempts = 0
    db.commit()
    db.refresh(user)

    record_audit(db, user.id, "PASSWORD_RESET_COMPLETED", "users", {})
    return user


@router.post("/accept-safety", response_model=UserOut)
def accept_safety_terms(
    payload: AcceptSafetyRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    current_user.safety_accepted = payload.accepted
    current_user.safety_accepted_at = datetime.now(timezone.utc)
    current_user.safety_policy_version = payload.policy_version
    db.commit()
    db.refresh(current_user)

    record_audit(db, current_user.id, "SAFETY_TERMS_ACCEPTED", "users", {"version": payload.policy_version})
    return current_user
