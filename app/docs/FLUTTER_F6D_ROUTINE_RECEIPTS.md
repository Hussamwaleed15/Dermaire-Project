# F6d-2 — Keyed routine configuration recovery

2026-10-18. Continuation after product receipts04e6e9114fbf4778d5c89979611ffbfccc8bfae5.
Actual backend RoutineOut/update/create and ConfigurationAttempt service inspected.

Routine create now POSTs its exact key/body; editing and stopping via existing
PATCH active:false preserve their original key, changed-field payload and quoted
If-Match. The UI's stop is an update receipt, not the separate DELETE stop identity.
The existing preflight continues to compare the original reviewed timestamp and
revision. Explicit retry after unknown bypasses a fresh-edit preflight and repeats
only the exact original keyed request/CAS, allowing the backend's original-receipt
replay to run before current business/revision checks. No silent rebasing/new key.

ConfigurationReceipt is narrowly shared with the actual backend's two foundation
configuration domains, not a synthetic universal receipt. It checks schema/owner/
actor/domain/operation/resource/revision/result_kind/times/snapshot_basis/availability.
Each repository validates its own original DTO. Routine uses RoutineOut, original
resource ID and revision; it does not pretend the receipt is the latest setting.
Adherence, products, clinician grants, Agent and plans retain their distinct APIs.

Existing routine screen exposes check-original, explicit retry-original after
unknown, and explicit finish-review for expired/erased content. Current routine
and adherence are independently refreshed. A newer current routine is not replaced
by the original configuration snapshot. Foreign/malformed/denied/readback-failed
receipts keep uncertainty. Unknown cannot be dismissed via expired-receipt review.
Logout/account generation rejects late results; original intent survives controller
reconstruction only within the same authenticated login. New configuration writes
are blocked while one is unresolved. Existing adherence behavior and its409
uncertainty are preserved; no new adherence key or calendar migration is invented.

Current response + individually confirmed resource readback resolves the write;
a subsequent failed list refresh marks data stale instead of creating an orphan
uncertain-operation lock with no retained key. Auth is checked before allocating
an operation, preserving typed session failures for unauthenticated service calls.

29 new mocked regressions: create/edit/stop before/after loss, exact key/body/header,
query resource scope, unknown/no replacement, newer current configuration, wrong
owner/domain/operation/resource/revision/result kind/basis/DTO,401/403/404/409/410/
412/422/428/503, expired/erased review, late logout and real stopped-step UI.
No live service, actual process-persistence proof or device certification claimed.

Final gate: all1681 tests pass (+29); analyzer clean; pub get succeeded. Device listing exposes macOS only; no emulator sources are configured. No mobile runtime claim.
