# Foundation doctor database clinical snapshot v2

GET `/api/v1/clinical-snapshot/patients/{patient_id}` is provisioned-doctor-only
under a current VIEW grant. It uses the same actual PostgreSQL REPEATABLE READ
transaction boundary as patient GET `/clinical-snapshot`, never SQLite emulation.
No migration beyond current source schema08 and no historical replay token.

Response extends the typed patient bundle with schema_version2, reader_id,
reader_role doctor, original access_id and explicit projection_visibility
`doctor_review_with_patient_home_and_psm`. Safety, review, home and PSM share one
evaluation clock and the same Safety result. The doctor's review field includes
authorized private notes/current private decision; home and PSM deliberately retain
their patient-facing projection. A private latest decision remains unavailable in
those patient projections; an older public decision never replaces it as current.
The visibility label makes this distinction explicit instead of pretending the
patient projections have clinician visibility.

Scope is DB rows visible in one transaction only. No image bytes, external
provider, model inference, independent endpoints, future time or exact commit
watermark is atomic here. Safety authority is preserved; clinical_clearance false,
replayable false, random correlation snapshot_id only. It grants no EXPORT scope.

Doctor, patient and grant locks fence ordinary authorization/revocation writers.
Immediately before returning private content, a separate READ COMMITTED session
rechecks current JWT/credential/logout, current stored doctor/patient roles and the
same original grant's active status, expiry and VIEW scope. Unknown/foreign/revoked
patient access403; patient/support/admin403; bad/expired/logged-out session401;
non-PG or serialization failure503 without clinical payload. Successful responses
set no-store and Pragma no-cache. No cross-request or external atomicity guarantee.

Tests include actual PG API scope/private-current checks, session revocation after
building a snapshot, and an independent-connection source/review update proving
two reads in one RR transaction do not mix versions. Normal API writers may block
on owner/grant locks; unguarded external writes are not represented as current
authorization. Deployment, managed transaction settings and performance remain
outside isolated verification.
