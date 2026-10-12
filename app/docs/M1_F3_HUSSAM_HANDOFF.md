# M1-F3 — Hussam handoff (backend-owned)

Flutter-only milestone. Existing POST/GET checkins support the current journey;
no essential form/history route is missing. The following known backend gaps
remain; this document is not permission for production changes.

## B1 — observation completion separate from metric baseline

Current POST /api/v1/checkins persists report-only observations (source=none).
GET /home.today_checked_in/journal and /baseline count confirmed metric records
only. Define an authoritative observation-completion field/projection for UTC
server day and expose the saved observation identity/as-of separately from
metric availability and baseline. Do not make report-only create scores, confirmed
measurement days or inferred clinical improvement. Preserve old metric semantics
or explicitly version a migration; publish response fixtures for Flutter.

Acceptance: a saved report-only ID appears in owned history and authoritative
observation completion; Home does not falsely prompt for another identical
observation; baseline/measurement fields remain unchanged/unknown as appropriate.
Wrong account/day, empty history, metric-only/combined records, deletion, refresh
failure and concurrent writes preserve their separate meanings.

## B2 — owner-scoped report-only idempotency / reconciliation

The existing idempotency_key header/fingerprint applies only when a photo is
present. Extend a durable atomic idempotency contract to report-only writes.
Define key location/format, canonical payload (time/report/safety/notes/optional
experiment), nullable-vs-omitted normalization, scope, retention/expiry and replay
status semantics. Bind owner from authenticated token, not caller-selected IDs.
Return the same saved record ID/original recorded fields/time for replay; provide
an owning-patient lookup/reconciliation contract for a key after lost response.

Required acceptance tests:

- Same account + same key + same canonical payload: one stored row, same record.
- Same account + same key + different payload: documented conflict (e.g. 409),
  no second row or mutation of the first.
- Different accounts: keys/results fully isolated; foreign lookup/replay denied.
- Concurrent duplicate requests, commit followed by timeout/disconnect, late
  client retry and process restart preserve the same identity/receipt.
- Define retained/in-flight/not-found/expired semantics. An empty history alone
  cannot prove failure or permit a blind resend while a commit may still happen.
- Account deletion erases lookup/request data and prevents replay restoring it;
  retention/privacy and transaction rollback/provider failures are covered.
- Unanswered safety values remain null/unknown, never false; replay does not
  rewrite current medical guidance or turn report-only into a measurement.

Flutter currently disables in-flight duplicates, sends once, uses explicit
uncertain outcomes and never claims exactly-once delivery. Exact-ID GET readback
can reconcile an unverified acknowledgement; a timeout with no ID cannot be
proved by matching content/time or inferred safety changes. No idempotency keys
are invented/sent as though the report-only backend honored them.

## Additional real contract limits (not required for this increment)

- GET /checkins is unpaginated and has no GET-by-ID/attempt route. Define stable
  owner-scoped cursor ordering and a lookup result shape if scalable history or
  lost-response reconciliation is needed. Preserve created_at/id ordering and
  duplicate/visibility/privacy semantics.
- Standalone /captures is not linked by report-only POST. New owner-validated
  capture-reference/observation linkage needs an explicit contract; no client
  heuristic combining captures/check-in IDs or metrics.
- Context currently supports unusual_conditions and cycle_day only. Do not add
  weather/sleep/stress/diet/medication/etc to check-in JSON until reviewed typed
  fields, nullable/disclosure/provenance and privacy semantics are published.
  No broad questionnaire is required merely because roadmap factors exist.
- Optional structured rejection receipts could state definitively not_committed
  under a documented contract. Flutter conservatively treats generic 5xx/
  malformed acknowledgements as uncertain rather than trusting a proxy error
  body to prove rollback.

Backend/Azure/database/AI/provider/Production/Tester were not changed or called.
Current M1-F2 safety/clinician contracts and precedence remain authoritative.
