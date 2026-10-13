# M6 — consolidated verified backend handoff for Hussam

Flutter M6 source started at65c3c75489ec752ca2b17a40aa16523a50be0ad0.
Backend/Azure/DB/AI/provider/Production/Tester unchanged; source inspection only.
No deployment, paid resources or live tests requested. Existing M1–M5/B1/B2
requirements remain separate, not silently resolved by M6.

## Existing contracts verified — do not recreate

- Live DB doctor role/credential/logout enforcement; trusted CLI provisioning.
  UserOut role is account provisioning, not clinical-license verification.
- Current patient/doctor identity, active expiry and grant authorization at each
  doctor list/detail/timeline/notes/reviews request; selected patient row/grant locks.
- Patient GET /doctor/access and selected DELETE /doctor/access/{id} with revoke
  timestamps/owner metadata; Flutter validates DELETE receipt and revoked GET.
- Immutable note GET/POST: content, priority, visibility, category, text follow_up,
  optional real timeline/review linkage. Flutter exposes safe editor fields only.
- Review GET/POST with expected_sequence409 + patient-row lock and
  UNIQUE(patient_id,sequence): actual server concurrency protection already exists.
  Current/history/actor/time, saved Safety and current comparison flags are real.
- Authorized doctor timeline with real offset/limit/total/next_offset. Includes source
  records and bounded deterministic context projections with availability/limits.
- GET /captures/{id}/image genuinely supports current doctor grants via image_access;
  Flutter restricts IDs to accepted stored records from that patient's timeline.
  Owner-only capture metadata/measurements/PSM routes are not reused for doctor reads.
- Patient review-status filters private notes/history and never falls back to an
  older visible decision when the newest action is private.

## P0 — explicit viewing/export consent before linking can resume

Confirmed in api/v1/doctor.py:generate_doctor_qr_access: QR creation sets
DoctorPatientAccess(export_consent=True) without explicit patient export selection.
GenerateQrResponse has token/expiry but access_out lacks separate scope/export
receipts. Flutter blocks both new QR generation and claim before HTTP, removes
placeholder QR/export-success/fixed-expiry/false revoke claims, and leaves existing
real grant reading/per-grant revocation available. This does not repair the backend.

Provide explicit separate patient view/export intent (no broader defaults), readable
clinician identity, authoritative scope/consent receipt and GET readback, owner and
actor binding, revocation, expiry and isolated negative tests (view-only must never
grant export; stale/revoked/foreign tokens/old sessions must fail). If license badges
are desired, expose an authoritative verification read model, not operator audit input.

## P1 — uncertain clinical operations

Lost POST/5xx/readback denial cannot prove rejection. Provide operation IDs,
idempotency keys, durable attempt/receipt lookup, replay-safe documented semantics,
and explicit committed/rejected/unknown outcomes with patient/doctor/grant scope.
Flutter locks uncertain operations within the session; valid receipt candidates can
be reconciled by GET only. It makes no exactly-once or restart-safe guarantee.
Do not request note editing or sequencing from scratch; immutable writes/CAS exist.

## P1 — genuine doctor-patient messaging (currently absent)

Define authorized conversation identity/participants, explicit patient consent and
live grant/revocation rules; durable message create/list with server IDs/actor/time,
pagination and operation lookup; supported delivery/read states with authoritative
receipts, not inferred sends; retention/account deletion and notification semantics.
If attachments are supported, specify scoped authenticated bytes, limits, lifetime
and separate export intent. Patient AI /chat cannot stand in for clinician messages.
Flutter messaging remains BLOCKED; no local fake inbox, sender or success feedback.

## P1 — scheduling (currently absent)

ClinicalNote.follow_up free text and follow_up_needed state exist. For appointments
or reminders, provide typed dates/timezones, actor/provenance, patient choice/consent,
current role/grant checks, revision/idempotency, cancellation and notification-delivery
contracts. Flutter displays text/state only; no default dates or comparison schedules.

## P2 — longitudinal consistency/completeness

Dynamic offset pages/built_at are not stable snapshots. Mutable source rows are not
edit histories; derived context is limited to14 recent records/240 facts. If stable
longitudinal read/export is required, provide snapshot/cursor and completeness/
retention limits, explicit capture-observation linkage and safe history pagination.
No complete medical-history or causal-treatment-effect guarantee is made in Flutter.
A continuous revocation/change feed is absent; current server authorization is
checked per request and client expiration closes views.
