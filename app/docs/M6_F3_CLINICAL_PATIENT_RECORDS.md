# M6-F3 — authorized clinical evidence (COMPLETE for supported evidence)

Source before phase: bfae6b9ac5aeff431757f448b381a4cf1455aedd.
Flutter only. Inspected doctor detail/timeline/reviews, doctor_loop.timeline,
context_builder projections and image_access.image_response. No owner-only
/captures metadata, /measurements or /personal-skin-model request is reused for a
selected patient. GET /doctor/patients/{id}/timeline is authorized per patient;
its response has no patient_id, so the immutable request/connection supplies scope.
The genuine GET /captures/{captureId}/image supports doctor grants and remains the
sole private image path. Fresh detail/grant verification precedes each read.

Added typed source/provenance/current/history readers, selected-patient revision,
scoped timeline controller and clinical evidence screen. Safety is separate and
first, never downgraded by clinician text. Patient reports, nonclinical image
estimates, manual tracking values, deterministic PSM/context projections and
clinician authors have distinct labels. Missing values remain unknown; fractions
are not percentages/diagnostic severity, evaluations are association not efficacy.
Legacy AI output stays quarantined. Supported fields are bounded/allowlisted;
no arbitrary raw DTO, secrets, public URLs, causal diagnosis or medical clearance.
Private clinician decisions can be read by an authorized doctor; current decision
must match latest sequence, historical decisions cannot replace it.

Real offset/limit/total/next_offset paging, oldest first; 100 per page, 500 display
cap explicitly disclosed. Duplicate/changed pages fail closed; page built_at is
not a stable cross-page snapshot. Mutable records are snapshots, derived context
has 14-record/240-fact limits with reported availability/truncation. Unknown sources
are labeled unsupported. Valid product ingredient identity suffixes and PSM colon
source IDs are preserved. No complete medical-history claim.

Images load only on explicit selection from a confirmed accepted Azure-backed
capture timeline record. Owner/role/generation/patient/grant/revision/disposal scope
is checked before/after request, streaming and decoding. Closed scopes dispose
pixels. No ImageProvider/global image cache/disk/export. PNG/JPEG, 64MiB transport,
16MP source, 1600px viewer and global 12MP decoded/reserved budget remain enforced.
Existing patient gallery/comparison behavior preserved. No automatic bulk images.

33 new mocked service/model/widget tests: status401/403/404/500, timeout/offline,
malformed/foreign provenance, exact paging/overlap/changed total, late logout/account/
patient/disposal, private-image authorization/MIME/status/late bytes, nonclinical
units, missing values, PSM and evaluation limits, 320px/200% light/dark/reduced motion.
Full analyzer/test results recorded below after final gate.
No simulator/emulator/device/native build/Production HTTP/backend/Tester edits.

Final gate: flutter analyze **No issues found**; full flutter test **1260 passed**
(1227 preserved +33 new). Existing private capture history/comparison/limits suites
remain passing; no assertions weakened.
