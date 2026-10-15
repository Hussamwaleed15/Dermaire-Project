from datetime import datetime, timezone, timedelta
import pytest
from pydantic import ValidationError
from tests.test_doctor_loop import loop, grant, review, auth, ROOT
from app.schemas import ClinicalNoteOut
from app.schemas.doctor_loop import ReviewActionOut, ReviewStatusOut
from app.main import app


def test_registered_clinical_dtos():
    paths=app.openapi()["paths"]
    expected=[("/api/v1/doctor/review-status","get","200","ReviewStatusOut"),
              ("/api/v1/doctor/patients/{patient_id}/reviews","get","200","ReviewStatusOut"),
              ("/api/v1/doctor/patients/{patient_id}/reviews","post","201","ReviewActionOut"),
              ("/api/v1/doctor/patients/{patient_id}","get","200","DoctorPatientDetailOut"),
              ("/api/v1/doctor/patients/{patient_id}/timeline","get","200","DoctorTimelineOut")]
    for path,method,status,dto in expected:
        assert paths[path][method]["responses"][status]["content"]["application/json"]["schema"]["$ref"].endswith("/"+dto)


def test_typed_review_notes_compatibility_and_follow_up(loop):
    client,db,patient,_,doctors=loop
    grant(loop)
    action=review(loop,patient_visible=True).json()
    dto=ReviewActionOut.model_validate(action)
    assert dto.schema_version=="clinical-review-1.0" and dto.resource_revision==dto.sequence
    assert action["created_at"].endswith("Z")
    note=client.post(ROOT+"/patients/patient/notes",headers=auth(doctors[0]),json={"content":"Synthetic clinical note", "patient_visible":True,"follow_up":"Discuss at next routine review"}).json()
    assert note["schema_version"]=="clinical-note-1.0"
    assert note["follow_up"]=="Discuss at next routine review"
    assert note["created_at"].endswith("Z") and note["updated_at"].endswith("Z")
    assert not any(key in note for key in ("scheduled_at","appointment","due_at"))
    status=client.get(ROOT+"/review-status",headers=auth(patient)).json()
    validated=ReviewStatusOut.model_validate(status)
    assert validated.current_decision.id==action["id"]
    assert validated.notes[0].doctor_id==doctors[0].id
    assert review(loop).status_code==409
    assert client.get(ROOT+"/patients/patient/timeline",headers=auth(doctors[0])).status_code==200


@pytest.mark.parametrize("change",[{"state":"diagnosed"},{"resource_revision":99},{"provenance":"ai_inferred"},{"clinical_clearance":True},{"safety_at_review":{"status":"track"}}])
def test_malformed_review_output_rejected(loop,change):
    grant(loop)
    payload=review(loop).json()
    with pytest.raises(ValidationError):ReviewActionOut.model_validate({**payload,**change})


def test_nullable_notes_and_offset_normalization():
    stamp=datetime(2026,1,1,3,tzinfo=timezone(timedelta(hours=3)))
    note=ClinicalNoteOut(id="note",doctor_id="doctor",patient_id="patient",content="Synthetic note",priority="routine",patient_visible=False,created_at=stamp,updated_at=datetime(2026,1,1))
    assert note.follow_up is None and note.timeline_item_id is None and note.review_action_id is None
    assert note.created_at==note.updated_at==datetime(2026,1,1,tzinfo=timezone.utc)
    with pytest.raises(ValidationError):ClinicalNoteOut.model_validate({**note.model_dump(),"priority":"diagnosis"})


def test_status_cannot_promote_history_or_foreign_owner(loop):
    client,db,patient,_,_=loop
    grant(loop)
    review(loop,patient_visible=True)
    review(loop,expected_sequence=1,patient_visible=False)
    data=client.get(ROOT+"/review-status",headers=auth(patient)).json()
    assert data["current_decision"] is None and not data["history"][0]["is_current"]
    with pytest.raises(ValidationError):ReviewStatusOut.model_validate({**data,"current_decision":data["history"][0]})
    with pytest.raises(ValidationError):ReviewStatusOut.model_validate({**data,"patient_id":"foreign"})
