import hashlib
import hmac
import json

from sqlalchemy import or_

from app.core.config import settings
from app.models import (User, Product, Experiment, ExperimentEvaluation, CheckIn, DoctorPatientAccess,
                        ClinicalNote, RewardRedemption, AuditLog, DailyContext, RoutineEntry, RoutineAdherence)
from app.services.azure_blob import azure_blob_service
from app.models import Capture, Measurement, ProductIntelligence, DoctorReviewAction


def delete_account(db, user_id):
    user = db.query(User).filter(User.id == user_id).with_for_update().first()
    if user is None:
        return  # A valid access token can retry after the response was lost.
    owned_models = (ProductIntelligence, Measurement, Capture, ExperimentEvaluation, RoutineAdherence, DailyContext, CheckIn, Experiment, RoutineEntry, Product, RewardRedemption)
    identifiers = {user_id, user.email, user.full_name}
    for model in owned_models:
        identifiers.update(row.id for row in db.query(model).filter(model.user_id == user_id))
    related = or_(DoctorPatientAccess.patient_id == user_id, DoctorPatientAccess.doctor_id == user_id)
    identifiers.update(row.id for row in db.query(DoctorPatientAccess).filter(related))
    actions = or_(DoctorReviewAction.patient_id == user_id, DoctorReviewAction.doctor_id == user_id)
    action_ids = [row.id for row in db.query(DoctorReviewAction).filter(actions)]
    identifiers.update(action_ids)
    # A note by another clinician can link to an action by the deleted doctor.
    notes = or_(ClinicalNote.patient_id == user_id, ClinicalNote.doctor_id == user_id,
                ClinicalNote.review_action_id.in_(action_ids))
    identifiers.update(row.id for row in db.query(ClinicalNote).filter(notes))
    # Refuse inconsistent legacy links rather than mutate another account.
    experiment_ids = db.query(Experiment.id).filter(Experiment.user_id == user_id).scalar_subquery()
    product_ids = db.query(Product.id).filter(Product.user_id == user_id).scalar_subquery()
    foreign_checkin = db.query(CheckIn.id).filter(
        CheckIn.user_id != user_id, CheckIn.experiment_id.in_(experiment_ids)).first()
    foreign_experiment = db.query(Experiment.id).filter(
        Experiment.user_id != user_id, Experiment.product_id.in_(product_ids)).first()
    entry_ids = db.query(RoutineEntry.id).filter_by(user_id=user_id).scalar_subquery()
    foreign_entry_experiment = db.query(Experiment.id).filter(
        Experiment.user_id != user_id, Experiment.routine_entry_id.in_(entry_ids)).first()
    capture_ids = db.query(Capture.id).filter_by(user_id=user_id).scalar_subquery()
    foreign_measurement = db.query(Measurement.id).filter(
        Measurement.user_id != user_id, Measurement.capture_id.in_(capture_ids)).first()
    foreign_intelligence = db.query(ProductIntelligence.id).filter(
        ProductIntelligence.user_id != user_id, ProductIntelligence.product_id.in_(product_ids)).first()
    if foreign_checkin or foreign_experiment or foreign_entry_experiment or foreign_measurement or foreign_intelligence:
        raise RuntimeError("Inconsistent cross-account links require repair before deletion")
    # Refuse a namespaced image reference pointing to another owner before deleting anything.
    for model in (Capture, CheckIn):
        for row in db.query(model).filter_by(user_id=user_id):
            key = row.image_blob_name
            if key and key.count("/") >= 2 and not key.startswith(f"skin_photos/{user_id}/{user_id}_"):
                raise RuntimeError("Inconsistent image ownership requires repair before deletion")
    # Keep ownership records until ALL external deletes succeed. Partial cleanup
    # can safely retry because deleting an absent blob is a no-op.
    for capture in db.query(Capture).filter_by(user_id=user_id):
        if capture.image_blob_name:
            azure_blob_service.delete_image(capture.image_blob_name)
    for checkin in db.query(CheckIn).filter(CheckIn.user_id == user_id):
        if checkin.image_blob_name:
            azure_blob_service.delete_image(checkin.image_blob_name)
    azure_blob_service.delete_owned_images(user_id)
    pseudonym = hmac.new(settings.SECRET_KEY.encode(), user_id.encode(), hashlib.sha256).hexdigest()[:32]
    for audit in db.query(AuditLog):
        serialized = json.dumps(audit.details or {})
        if audit.actor_id == user_id or any(value and value in serialized for value in identifiers):
            if audit.actor_id == user_id:
                audit.actor_id = pseudonym
            audit.details = {}
            audit.ip_address = None
    db.query(ClinicalNote).filter(notes).delete(synchronize_session=False)
    db.query(DoctorReviewAction).filter(actions).delete(synchronize_session=False)
    db.query(DoctorPatientAccess).filter(related).delete(synchronize_session=False)
    # Explicit dependency order also works with enforced database foreign keys.
    for model in owned_models:
        db.query(model).filter(model.user_id == user_id).delete(synchronize_session=False)
    db.query(User).filter(User.id == user_id).delete(synchronize_session=False)
    db.add(AuditLog(actor_id=pseudonym, action="ACCOUNT_DELETED", target_resource="users", details={}))
    db.commit()
