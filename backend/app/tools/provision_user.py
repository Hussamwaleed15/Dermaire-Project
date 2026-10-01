"""Trusted-host CLI only. This module must never be exposed as a public route."""
import argparse
import getpass
import hashlib
import sys
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, SecretStr, ValidationError, field_validator
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError

from app.core.database import SessionLocal
from app.core.exceptions import DermaireException
from app.core.security import get_password_hash
from app.models import AuditLog, User


class ProvisionRequest(BaseModel):
    email: EmailStr
    full_name: str = Field(min_length=2, max_length=100)
    role: Literal["doctor", "admin", "support"]
    password: SecretStr
    verification_reference: str = Field(min_length=3, max_length=200)
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    @field_validator("password")
    @classmethod
    def validate_password(cls, value):
        password = value.get_secret_value()
        if len(password) < 12 or len(password.encode("utf-8")) > 72:
            raise ValueError("Password must have at least 12 characters and at most 72 UTF-8 bytes")
        return value


def provision_user(db, request: ProvisionRequest, *, operator: str):
    """Call only from an operator-controlled host with trusted DB credentials.

    Shell/database access is the authorization boundary, not an HTTP token or
    client-provided role. Existing accounts are never elevated or overwritten.
    """
    if not operator.strip():
        raise ValueError("A trusted operator identity is required")
    email = str(request.email).lower()
    if db.query(User.id).filter(func.lower(User.email) == email).first():
        raise DermaireException("Account already exists; no role or password was changed.",
                                "EMAIL_ALREADY_EXISTS", 409)
    user = User(email=email, full_name=request.full_name, role=request.role,
                hashed_password=get_password_hash(request.password.get_secret_value()),
                safety_accepted=False, tokens_balance=0, baseline_checkins_count=0)
    try:
        db.add(user)
        db.flush()
        db.add(AuditLog(
            actor_id="operator:" + hashlib.sha256(operator.encode()).hexdigest()[:27],
            action="PRIVILEGED_ACCOUNT_PROVISIONED", target_resource="users",
            details={"user_id": user.id, "role": user.role,
                     "operator": operator, "verification_reference": request.verification_reference},
        ))
        db.commit()
    except IntegrityError:
        db.rollback()
        raise DermaireException("Account could not be provisioned because of a conflicting record.",
                                "PROVISIONING_CONFLICT", 409)
    except Exception:
        db.rollback()
        raise
    return user


def main(argv=None):
    parser = argparse.ArgumentParser(description="Provision a verified privileged account on a trusted backend host")
    parser.add_argument("--email", required=True)
    parser.add_argument("--full-name", required=True)
    parser.add_argument("--role", required=True, choices=["doctor", "admin", "support"])
    parser.add_argument("--verification-reference", required=True, help="Internal identity/approval reference; no medical data")
    args = parser.parse_args(argv)
    if not sys.stdin.isatty():
        parser.error("An interactive terminal is required; passwords must not be supplied in arguments or scripts")
    password = getpass.getpass("New account password: ")
    confirmation = getpass.getpass("Confirm password: ")
    if password != confirmation:
        print("Passwords do not match. No account was created.", file=sys.stderr)
        return 1
    try:
        request = ProvisionRequest(email=args.email, full_name=args.full_name, role=args.role,
                                   verification_reference=args.verification_reference, password=password)
    except ValidationError as error:
        # Never print validation input: it may contain the plaintext password.
        fields = ", ".join(".".join(str(part) for part in item["loc"]) for item in error.errors())
        print(f"Invalid provisioning fields: {fields}. No account was created.", file=sys.stderr)
        return 1
    with SessionLocal() as db:
        try:
            user = provision_user(db, request, operator=getpass.getuser())
        except DermaireException as error:
            print(error.message, file=sys.stderr)
            return 1
        except Exception:
            print("Provisioning failed. No successful operation was confirmed.", file=sys.stderr)
            return 1
        print(f"Provisioned {user.role} account {user.id}. No login token was issued.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
