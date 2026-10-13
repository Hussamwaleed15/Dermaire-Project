# M5-F3 — routine timing disclosure (PARTIAL; scheduling BLOCKED)

Starting source: M5-F2 commit 621d9da (remote verification recorded in report).
Audited backend/api/v1/routine.py, schemas/routine.py, services/routine.py,
models RoutineEntry/RoutineAdherence, experiment schemas/services and doctor
review resources. Existing schedule is AM/PM/BOTH, daily, start/end dates,
am_order/pm_order. Reports use UTC calendar days and configured slots; missing
reports are unknown adherence. These are grouping/report contracts, not wall
clock reminder times, timezone/quiet-hour settings or delivery jobs. Existing
adherence uniqueness does not authorize scheduling or clinical follow-up.

No reminder or typed follow-up scheduling resource/receipt, device dispatch,
push opt-in, IANA timezone/DST policy, persisted doctor/authorized AI comparison
schedule or patient confirmation lifecycle exists. An experiment target/end
is not a medical comparison date. ClinicalNote.follow_up is an existing optional free-text field, not a typed
due-time/timezone or scheduling receipt. The backend review projection includes
patient-visible notes, but current Flutter ClinicianReview renders the current
decision/state rather than a note feed. Neither follow_up text nor the real
follow_up_needed review state is interpreted into a scheduled operation.

Completed: routine now explicitly explains grouping versus clock time, absent
scheduled reminders and the requirement for confirmed clinical follow-up/photo
comparison guidance. Actual M4 user routine/edit/adherence/UTC behavior preserved.

No local notification scheduler/dependency/persistence or prompt added. A complete
user reminder would need permission, explicit chosen times, cancellation,
rescheduling, timezone/DST, restart reconciliation and account-aware cancellation
with privacy-safe payloads. Adding only a mocked boundary or incomplete durable
jobs would risk cross-account delivery. Neither server nor local scheduling is
claimed complete. Native/device validation remains external and was not run.

Six new regression widgets: AM/PM/BOTH in Light/Dark, 320px/200% text/reduced motion,
existing grouping retained, no time-picker/enable control, no permission request,
no adherence/history fabricated. No new wire model/endpoints; existing fake
repositories and production HTTP denial preserved. Full prior authority tests run.
Validation: analyzer clean; full **1114 tests passed** (1108 + 6 new).
Existing M4 grouping/report widgets now explicitly scroll and settle before
asserting or tapping content below the added disclosure; no weakened assertions. Handoff: consolidated M5 document.
