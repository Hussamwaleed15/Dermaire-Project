# F6c-2 — Existing protected routine edits and stops

2026-10-18. Plan: inspect actual RoutineOut/update/stop schemas and revision
reservation before coding; preserve the step reviewed in the editor/stop dialog,
require its original revision for current versioned responses, send strong quoted
If-Match for already-protected rows, and exercise real screens with synthetic HTTP.
Do not opt unprotected steps in before linked experiment activation can supply its
required Routine-If-Match. No changes to native/backend/Tester/provider systems.

Current RoutineOut has revision/revision_protected. Both must be valid together
when present; legacy absence remains readable. The same validation applies to
actual adherence configuration snapshots without projecting today's configuration
into historical evidence. No version is inferred from updated_at or engine version.

Edit and stop pass original revision and updated_at. Stop uses the exact step from
its confirmation dialog, not a newer controller row obtained after confirmation.
A mismatching preflight produces a definite412-style conflict before dispatch;
server412 also closes a race after that read. Both require refresh and reopening
rather than silent rebasing. Existing protected steps send their original If-Match.
Unprotected steps remain unprotected for now: a matching header would permanently
opt them in and the existing experiment activation writer is not yet compatible
with protected linked routines. No end-to-end CAS guarantee for unprotected or
legacy rows is claimed. Experiment integration and opting in safely remain next.

PATCH is the existing actual UI stop route (active:false); history stays intact.
This does not invent resume, adherence, treatment deadlines or image comparisons.
Header transport is narrowly expanded to routine-entry PATCH, not arbitrary paths,
auth fields or adherence. Actual returned revision is consumed without guessing+1.
New receipt/history/restart contracts remain unintegrated in this increment.

Definite configuration PATCH rejections (conflict/precondition/validation) require a
fresh read but no longer permanently label an operation as uncertain. Timeout,
503, malformed/unconfirmed reply and failed readback stay uncertain and block a
second submission, even after a refresh. Adherence409 remains uncertain: uniqueness is not proof of the original report outcome. No new idempotency key, invented receipt
or automatic replay is introduced. Logout/account generation guards reject late
results. Safe conflict copy is visible in the actual editor; the draft remains.

Routine screen copy now points to separate Reminder settings rather than falsely
claiming reminders cannot be configured. It still distinguishes grouping from a
clock time and clinical follow-up scheduling. No reminder delivery is claimed.

24 new mock regressions cover invalid/partial metadata, protected edit and stop,
unprotected compatibility, same-timestamp changed revision, missing reviewed
revision,401/403/409/412/422/428/503, definite-rejection refresh versus uncertain
timeout, late logout, actual editor save and stale error feedback. Mock transports
deny production hosts. Existing routine/adherence/experiment tests remain required.

Final gate: pub get succeeded; analyzer clean; all1590 Flutter tests passed (+24). Existing adherence409 duplicate prevention remains unchanged. The existing Agent routine fixture now includes the actual required revision_protected field; copy tests retain clock/platform-side-effect guards with current reminder-settings text.
