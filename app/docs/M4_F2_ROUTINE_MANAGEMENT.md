# M4-F2 — routine management

Source HEAD before this phase: 5498acf32f4a405c7431c924fd90c835643b278b.
Verdict: supported daily entry management implemented; PARTIAL for strict atomic
concurrent-edit protection, which requires a backend revision precondition.

Inspected schemas/routine.py, api/v1/routine.py, services/routine.py and models.
Real identity is RoutineEntry.id + product_id. There is no plan/group ID,
clinician authorship, recurrence other than daily, reminder or comparison date.
RoutineOut.source is user_configured. UI labels cosmetic preferences separately
from clinician treatment; it cannot edit doctor treatment instructions.

Morning/Evening grouping uses AM/PM/BOTH and the respective integer order.
Stopped history remains visible. Add/edit supports only actual fields; a stopped
entry is immutable and requires a new entry to resume. Stop asks confirmation;
it preserves reports and creates no comparison schedule. Product selection uses
strict owned active personal records. Unsupported planner controls are absent.

Remote requests require current patient consent and session. Mutations validate
receipt, read back exact entry, then refresh GETs before displaying success.
PATCH checks original updated_at and sends changed fields only. Backend handles
experiment locks/conflicts; without expected_version this is a preflight guard,
not atomic race protection. Uncertain operations are locked in this session;
refresh is GET-only, not POST replay. Previous confirmed data remains explicitly
stale on failure and cannot be edited. Duplicate saves, old responses/disposal,
old dialogs, logout and account changes cannot show success for another account.
Dialog text clears on session invalidation. Existing fixtures updated for truthful
stale retention and stop confirmation, without removing tests.

Tests: 16 new parsing/remote-readback/lifecycle/grouping regressions, all prior
Flutter tests retained. Full analyze and full test gates recorded per phase in
final report. Mocks only, global production-host denial unchanged. No device QA.

Hussam: add atomic expected_version to entry PATCH and owner-scoped operation
lookup/idempotency for POST entries; publish timestamps with UTC offset and
explicit authored_by/permission metadata before clinician editing is offered.
