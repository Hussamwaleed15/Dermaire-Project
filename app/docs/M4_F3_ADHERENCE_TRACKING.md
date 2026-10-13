# M4-F3 — adherence reports and history

Source HEAD before phase: 7dd7445fb7e7b68d83e0ed9113bbad442f9ad60d.
Verdict: supported completed/skipped report workflow and paginated history
implemented; no reminders, clinical completion score or invented streaks.

Re-inspected actual RoutineAdherence model, routine schema, route and service.
POST/routine/adherence201 records routine_entry_id/date/AM-or-PM/status/note.
GET supports limit/offset and optional routine_entry_id, no total or as_of.
Unique constraint (routine_entry_id,date,slot) DOES exist: duplicate409 is real.
This corrects any prior handoff suggesting duplicates were not constrained;
uniqueness still does not provide a mutation receipt/idempotency lookup.

Only completed/skipped are supported. Server restricts dates to current entry
configuration/start day through server UTC today, configured slot, active product
and eligible active step (or skipped for its active stop experiment).
The selected UTC report date starts from device UTC and stays explicit; backend
validates it. Date selection is not a treatment deadline or local clinical reset.
No Home today_checked_in, baseline, observation, capture or experiment evidence
state is mutated by Flutter adherence success.

POST receipt must contain valid dated report and actual configuration snapshot,
with matching entry/slot/source. Filtered GET must return the same persisted
receipt before success; a checkbox/tap or POST timeout cannot confirm use.
This is a server-confirmed USER REPORT, not objectively verified adherence.
Pending duplicate taps are blocked. Uncertain entry/day/slot remains locked
through GET refresh; independently confirmed records can be shown honestly.
Offline history keeps previously confirmed events with a stale warning; changes
remain unavailable. Old session responses cannot repopulate records.

History loads real offset pages of 100, preserves immutable snapshots/timestamps
and fails on overlapping pages instead of claiming a complete dataset. There is
no total, snapshot cursor or overall percentage. Load older reports is available
only when a page has 100 records. Concurrent insertion can shift offset history;
refresh is the honest recovery. Server may reject old-date reports after edits.
Notes returned by server are displayed; the quick report UI submits no note.

17 new regressions: malformed snapshots/sources/dates/slots, confirmed receipt,
missing GET readback, timeout/403/409/503, no blind retry, offset/overlap/offline/
late-clear history. Full analyzer and Flutter suite gate recorded in final report.
All synthetic, production hosts denied. Device clock and real-device QA remain.

Hussam: optional stable cursor/as_of plus receipt lookup/idempotency semantics;
provide server date in routine read model and versioned configuration if historic
report editing is required. Do not resolve observation/Home B1 through adherence.
