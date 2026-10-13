# M6-F4 — clinical notes, reviews and text guidance

COMPLETE for the supported immutable records. Scheduling remains BLOCKED.
Source before phase: d0429f32520afb020c70729259ba4b2c0b0af36a.
Inspected ClinicalNoteCreate/Out, ReviewActionCreate, note/review GET/POST,
authorize patient-row lock, add_review expected_sequence409 and database
UNIQUE(patient_id,sequence). The backend already has atomic sequencing and
append-only notes/reviews; no PATCH/update/cancellation/appointment contract.
No backend changes or real requests were made.

New selected-patient clinical controller and editor support note content10–1500,
priority routine/review/urgent, explicit visibility (default private), category1–50,
optional follow_up100 free text. Notes are append-only, authored and timestamped;
no editing past records. Review state pending/in_review/reviewed/follow_up_needed,
optional SafetyState recommendation with rationale10–1500, explicit visibility and
real expected_sequence. Current state/history/latest sequence/author/timestamp and
saved Safety snapshot remain separate from canonical current Safety. Historical
and private latest decisions cannot be replaced by an old visible recommendation.
No license verification, AI clinical write, prescription/automatic comparison change.

Fresh grant preflight, exact payload fields, current review sequence preflight,
server CAS, global per-session write exclusion, actor/patient/access/sequence and
field-valid receipt, authoritative notes/reviews readback precede saved UI.409 or
stale editor requires manual refresh/reconsideration. A newer review during readback
is explicitly current, the confirmed submitted record is historical. Dynamic
Safety comparison flags may change; immutable review fields/saved Safety must match.

POST receipt then denied/lost GET is uncertain. Unknown receipts/timeout/5xx/offline
cannot be treated as rejected. Session-memory uncertainty survives editor recreation;
no automatic POST replay. Valid receipt candidates allow GET-only reconciliation;
no candidate after a lost POST means operation lookup/idempotency remains needed.
Logout/account change clears candidates, locks and records. Selected-patient changes
clear the old editor and prevent old success/error/readback from reaching the new one.
Legacy unused note writer also binds selection and shares global exclusion.

Patient clinical detail now separately displays only server-returned patient-visible
notes/guidance, author/time, without substituting notes for the current decision.
Private/foreign/malformed note rows are withheld independently; canonical Safety
and current review survive note parsing failure. Stale reads are labeled previous.
Patient-visible means a server record, never message delivery/read or export consent.

Follow-up is text and follow_up_needed is a workflow state. No calendar/default date,
reminder/notification delivery or automatic comparison scheduling is created.
Optional server note timeline/review linkage fields exist but are not exposed in
this editor; no arbitrary IDs are supplied. True scheduling/messaging/export unavailable.

48 new isolated service/model/widget tests: all note/review statuses, receipt/readback,
409/stale sequence/supersession, validation, timeout/offline/5xx uncertainty, rejected
writes, GET reconciliation/no replay, duplicate writes, grant/role invalidation,
logout/doctor/patient switch and old/current401, private current vs visible history,
patient note scope and full-form 320px/200% light/dark/reduced-motion regressions.
No Production hosts, OAuth, device, emulator, simulator or native builds.

Final gate: flutter analyze **No issues found**; full flutter test **1308 passed**
(1260 preserved +48 new). All earlier M1–M5 and M6-F1–F3 regressions preserved.
