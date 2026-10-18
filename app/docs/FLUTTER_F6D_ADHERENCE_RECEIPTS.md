# F6d-4 — Immutable adherence report receipts

2026-10-18. Actual AdherenceCreate/Out/AttemptLookup, routine routes and
adherence_attempts service inspected before implementation. Builds on3285a1b.

Routine report POST now freezes one exact key/body in the authenticated session.
Adherence has no If-Match or configuration CAS input: the actual server freezes the
configuration revision at commit. That immutable revision belongs to the original
report, not today's edited step. UTC report-day identity remains unchanged; no
local-day migration or backfill policy is invented.

AdherencePending/AdherenceReceipt are separate from ConfigurationAttempt. They
validate schema/operation/owner/actor, report ID=attempt/resource ID, committed and
expiry instants, original config revision, original date/slot/status/note, UTC basis,
report creation instant and identical nested receipt. A keyed success requires a
real receipt; legacy history rows remain readable without invented metadata.

The existing routine view exposes check-original-report, explicit exact retry after
unknown, and explicit expired-receipt history review. New reports are blocked while
one is unresolved; changed drafts/selected day cannot replace its original body.
First validation422 permits a separate reviewed report;409 is not proof of the
original request and remains uncertain even if another report occupies that slot.
No new key is generated for retry. Logout/session change rejects late history.

Current history is fetched separately and kept at its actual bounded100-item page.
Attempt lookup reads the owned immutable record; an older original outside that
page can confirm the request without inserting it into newer history or rewriting
its config snapshot. A known POST response plus valid full current history window
also does not claim a historical record is in that window. A truncated window's
absence is not failure. Contradictory immutable rows or malformed history fail
closed. Expired review never recreates content or repeats a report.

Controller locks across product/routine/experiment views now clear after a fresh
successful read only when the shared authenticated pending operation has actually
been resolved elsewhere. Merely refreshing an unresolved operation still cannot
unlock a replacement. This fixes orphan UI locks across controller instances.

Existing mocked HTTP fixtures for successful reporting now include real keyed
receipt fields and frozen config revisions. Legacy memory/history fixtures stay
legacy; assertions for401/403/409/timeout/503, missing readback, UTC semantics and
actual integrated journeys remain. No assertion is removed to force a green gate.

28 new regressions: before/after loss, exact key/body without CAS, original versus
new config, unrelated occupied slot, actor/slot/date/note/report/config/time/nested
receipt contradictions, lookup401/403/404/409/410/422/503, expired review, late logout,
actual routine report recovery, three cross-controller resolutions, bounded history
without historical insertion, and definite422 followed by reviewed replacement.
No process-restart, disk-durability or real mobile/backend E2E claim. F6e storage
and device verification blockers remain unchanged; no native changes were made.

Final gate: pub get succeeded; analyzer clean; all1741 Flutter tests passed (+28).
