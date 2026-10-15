"""One DB snapshot, one Safety, distinct doctor review/patient projections."""
from app.schemas.doctor_snapshot import DoctorClinicalSnapshotOut
from app.schemas.doctor_loop import ReviewStatusOut
from app.services.clinical_snapshot import build_snapshot,CONSISTENCY
from app.services.doctor_loop import review_status


def build_doctor_snapshot(db,patient,doctor,grant):
    bundle=build_snapshot(db,patient)
    review=review_status(db,patient,patient_view=False,now=bundle.evaluated_at,safety=bundle.safety)
    review["consistency"]=CONSISTENCY
    data=bundle.model_dump()
    data.update(schema_version=2,reader_id=doctor.id,access_id=grant.id,review=ReviewStatusOut.model_validate(review))
    return DoctorClinicalSnapshotOut.model_validate(data)
