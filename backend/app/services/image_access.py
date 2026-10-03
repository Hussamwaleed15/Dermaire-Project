"""Authenticated image responses; no transferable URLs or local fallback."""
from fastapi import HTTPException, Response
from app.services.azure_blob import azure_blob_service
from app.services.doctor_loop import authorize


def safe_reference(value):
    # Legacy external references are never published or used as network URLs.
    return value if value and ":" not in value and "?" not in value and "#" not in value else None


def image_response(db, user, row):
    if row is None:
        raise HTTPException(404, "Image not available.")
    if row.user_id != user.id:
        if user.role != "doctor":
            raise HTTPException(404, "Image not available.")
        authorize(db, user, row.user_id)
    if not safe_reference(row.image_blob_name) or not row.image_blob_name.startswith(f"skin_photos/{row.user_id}/{row.user_id}_"):
        raise HTTPException(404, "Image not available.")
    try:
        data = azure_blob_service.read_capture(row.image_blob_name)
    except Exception as exc:
        from azure.core.exceptions import ResourceNotFoundError
        if isinstance(exc, ResourceNotFoundError):
            raise HTTPException(404, "Image not available.")
        raise HTTPException(503, "Image storage unavailable; retry later.")
    return Response(data, media_type="image/jpeg" if data.startswith(b"\xff\xd8") else "image/png", headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"})
