# F6 L continuation —2026-10-18

Start c7eb85f85a49610760620c7ccb09bfbd6324d6cc; origin fetch/push verified,
clean shared main, fetch0/0. Baseline pub get/analyze and1808 tests passed.

## L1 selective withdrawal — DONE bounded session-memory contract

Actual backend/app/api/deps.py, api/v1/doctor.py, services/grant_attempts.py,
doctor_loop.py and AccessGrantOut inspected. GET doctor/access returns owned
sharing metadata without clinical records. DELETE doctor/access/id permits
withdrawal before current policy acceptance; key binds the original access ID.
GET doctor/consent-attempts/revoke/key returns historical owner/actor/access scope.

Safety entry → Manage clinician access → Choose one clinician grant now lists
validated owned metadata only, including original grant ID, clinician label,
status and expiry. Explicit selection plus scope confirmation are required.
Expired/revoked grants cannot be selected. A pending invitation can be revoked.
No safety acceptance, ordinary private read, invitation creation or shell bypass.

Original key/path/body remain frozen through loss and lookup. Unknown allows only
explicit exact retry after lookup; expired keeps replacement locked. Committed
receipt and independent current access-list verification must both validate the
original grant; later grants remain separate. Denied receipt clears metadata;
logout/background/account changes wipe displayed metadata and confirmation.
Late verification uses view generation. No process-death persistence claim.

Files: lib/consent/clinician_withdrawal.dart, lib/services/api_service.dart,
test/wave_selective_withdrawal_test.dart, test/wave_entry_withdrawal_test.dart.
The existing large-text bulk widget test now scrolls to lazily constructed controls
before tapping; no behavioral assertion was removed.

Verification:20 new tests; focused48, full1828, analyzer clean. Synthetic-host-only
unit/widget transport covers before/after-commit loss, duplicate submit, new grant,
wrong actor/grant/operation/current state, expiry,401/403/404/409/410/422/503,
hide/logout/switch late replies and320px/200% light/dark screen interactions.
No backend/Tester/native/Production changes; no real OAuth/device/backend E2E.

## L2a plan participation withdrawal — DONE bounded; L2 overall PARTIAL

Actual clinical_plans API/service authorize/mutate/attempt and CancelPlan inspected.
POST /clinical-plans/id/cancel permits policy-loss patient withdrawal even after
the original doctor grant is revoked; doctors still require their original grant.
CAS is payload expected_revision, not an invented If-Match header. Reason is fixed
nonclinical text; no free-text medical payload added.

New PlanWithdrawalScreen is linked from the actual Safety withdrawal hub. Dedicated
ApiService.planWithdrawalMetadata permits only owned patient list/detail/cancel/
cancel-attempt routes and strips purpose, snapshots, capture references, notes and
model results before returning data. The ordinary integration adapter still denies
private plan GET without current policy. Identity/kind/state/revision only are shown.
Explicit inline selected-plan confirmation is invalidated by refresh/hide/session;
covering dialogs are avoided because they invalidate the private route lifecycle.

PlanWithdrawalIntent freezes original patient/doctor/grant/plan, key and revision.
Original receipt and independent current state stay separate. First definite conflict
requires refresh and new explicit review; after uncertainty the original key remains
locked. No automatic rebase/replacement. Unknown permits explicit original retry;
expired remains unresolved. Metadata clears on failed reads and late results cannot
restore it. Cancellation is NOT evidence that a separate evaluation job was cancelled.
L2 evaluation-job policy-loss cancellation remains PARTIAL for a separate increment.

Files: lib/consent/plan_withdrawal.dart, clinician_withdrawal.dart,
lib/services/api_service.dart, test/wave_plan_withdrawal_test.dart. Gate:16 new tests,
focused44, full1844, analyzer clean. Fake HTTP only; no backend/device E2E claim.

## L4 decision / L10 environment

See FLUTTER_SECURE_RECOVERY_DECISION.md: concrete encrypted transaction journal and
platform key proposal, minimum data per domain, alternatives, migration/erasure,
crash tests and native approvals. Architecture assessment DONE; implementation and
process-death proof BLOCKED, no native changes. Fresh doctor/devices/emulators:
Flutter3.44.8, missing Android SDK, only macOS, no emulator sources; Xcode26.0.1
present, CocoaPods absent, existing SwiftPM preserved. Mobile runtime NOT RUN.
