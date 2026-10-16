# Recurring reminders and isolated notification worker

Migration `20261015_13` follows history/calendar `_11`; no data backfill or old UTC
adherence reinterpretation. Push remains unavailable; no delivery proof is invented.

Owner bearer routes:

* `GET /api/v1/notifications/routine-reminders/{entry_id}`: default revision0,
  enabled false and configured false. Foreign entries return404.
* `PUT` same path accepts only the explicit body below. Stale expected_revision409;
  enabling requires active owned routine and explicit routine-kind preferences.

```json
{"expected_revision":0,"enabled":true,"timezone":"Africa/Cairo","am_minute":540,"pm_minute":1260,"fold":0,"gap_policy":"skip"}
```

AM/PM/BOTH follows the entry's current schedule. The chosen wall minutes and IANA
zone are independent of device timezone and prospective account display labels.
A setting edit increments revision, fixes its effective UTC instant and cancels old
occurrences. A timezone/travel edit affects future generation only; old UTC instants
are never reinterpreted. Gaps skip that day; overlaps use exactly the explicit fold
once. Normal unambiguous times use fold0 regardless of overlap preference. Routine
start_date remains a legacy UTC threshold. No overdue/missed occurrence backfill.

Generator `app.services.routine_reminders.generate` accepts1..7 days and1..500
settings (default2 days/100). Fair oldest-generation ordering, per-owner locks,
entry+setting revision/local day/slot/fold occurrence identity and atomic SQL insert
prevent duplicate local enqueue. The executable worker runs generation plus bounded
outbox claims. Routine config edits/stop/archive cancel jobs in their transaction;
consent removal also disables schedules, and re-enabling preferences never revives
those schedules. Explicit schedule enablement is required again. Logout cancels
this session's pending jobs, erases encrypted device token and fences its lease.
Account deletion erases settings/notices/jobs. A routine push more than24h overdue
is cancelled, while authorized inbox history remains readable.

`PUT /notifications/{id}/unread` is an explicit owner/current-source transition;
future, foreign, cancelled or revoked-source notices404. `GET /notifications/history`
uses limit1..100 and optional owned before cursor. Returns privacy-filtered durable
current/cancelled state and prospective job-attempt records, without message/image/
device payload. Each worker lease records a start; an expired lease without fenced
completion becomes `unknown`, retries remain distinct, and provider acceptance is
`provider_accepted`. Every attempt keeps `delivery_confirmed: false`: this is local
attempt evidence, not provider transport proof. No pre-migration history is invented.
Revoked clinical sources are omitted. Routine cancellation history remains owner-
visible while the source exists. Account deletion erases attempt records. No
cancellation can retract a provider-accepted message.

Isolated CLI (run from backend after migrations against deliberately disposable DB):

```
python -m app.workers.notifications --database-url sqlite:///dermaire_rehearsal_worker.db --once
```

Only SQLite or the explicitly loopback gate127.0.0.1:55441/user gate/database
`dermaire_gate_*` is accepted; default application DATABASE_URL is never used by
this CLI. SQLite does not provide PostgreSQL multiworker locking guarantees.
Non-once mode polls at30 seconds by default; bounded1..300 seconds and max-jobs
1..1000. Output contains counts and false delivery proof, no identifiers/tokens/PHI.
Provider exceptions/invalid outcomes become retry without logging secrets. Existing
lease expiry/fencing/backoff/quiet-hour checks remain authoritative. Accepted means
only adapter acceptance; delivered has no implementation without genuine evidence.

Live enablement is BLOCKED: implement and independently review authenticated
provider transport, configure secrets outside source, verify provider idempotency,
transport timeouts, PHI-free request/logging and genuine receipt proof, validate
revocation races and real devices, review hosted scheduler/migrations/monitoring.
No flag in this increment enables live transport. Tests with injected fake adapters
are synthetic infrastructure evidence only, not device or clinical certification.
