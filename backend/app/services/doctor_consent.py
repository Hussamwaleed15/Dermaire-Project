"""Patient intent from an atomic audit receipt bound to the signed private QR.

Legacy export booleans are not evidence of explicit consent. No export endpoint
is implemented here; future export consumers must use authorize(scope="EXPORT").
"""
import jwt
from sqlalchemy.orm import object_session
from app.core.config import settings
from app.models import AuditLog


def consent_of(row):
    try:
        claims = jwt.decode(row.access_token, settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM], options={"verify_exp": False})
        binding = claims.get("consent", {})
        db = object_session(row)
        receipt = db.query(AuditLog).filter(
            AuditLog.actor_id == row.patient_id, AuditLog.action == "DOCTOR_QR_GENERATED",
            AuditLog.target_resource == "doctor_patient_access",
            AuditLog.details["access_id"].as_string() == row.id,
        ).first() if db is not None else None
        intent = receipt.details if receipt else {}
        if (claims.get("type") != "doctor_qr_access"
                or claims.get("patient_id") != row.patient_id
                or binding.get("version") != 2
                or binding.get("access_id") != row.id
                or intent.get("consent_version") != 2
                or intent.get("access_id") != row.id
                or intent.get("patient_id") != row.patient_id
                or row.granted_by != row.patient_id
                or intent.get("scopes") not in (["VIEW"], ["VIEW", "EXPORT"])
                or (intent.get("doctor_id") is not None and intent["doctor_id"] != row.doctor_id)):
            return None
        return intent
    except (jwt.PyJWTError, AttributeError, TypeError, ValueError):
        return None


def granted_scopes(row):
    intent = consent_of(row)
    # Existing active legacy grants retain clinical viewing, never legacy export.
    if intent is None:
        return ["VIEW"] if row.status in ("active", "revoked", "expired") else []
    return ["VIEW", "EXPORT"] if row.export_consent is True and "EXPORT" in intent["scopes"] else ["VIEW"]
