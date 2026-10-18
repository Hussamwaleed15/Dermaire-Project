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
