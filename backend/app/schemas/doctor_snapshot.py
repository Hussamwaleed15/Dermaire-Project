from typing import Literal
from app.schemas.clinical_snapshot import ClinicalSnapshotOut


class DoctorClinicalSnapshotOut(ClinicalSnapshotOut):
    schema_version: Literal[2]=2
    reader_id: str
    reader_role: Literal["doctor"]="doctor"
    access_id: str
    projection_visibility: Literal["doctor_review_with_patient_home_and_psm"]="doctor_review_with_patient_home_and_psm"
