# H5 messaging contract v1

Registered `/api/v1/messaging` endpoints:

| Method/path | Input | Result |
|---|---|---|
| POST /threads | `{ "access_id": "grant-id", "messaging_consent": true }` | 201 thread; replay enrollment returns same thread |
| GET /threads | current authenticated patient or doctor, limit 1..100, after=owned thread id | active consented original-grant threads, next_after cursor |
| POST /threads/{id}/messages | `{ "body": "Please review my progress" }`, one Idempotency-Key | 201 immutable message, Operation-Attempt-Id |
| GET /threads/{id}/attempts/{key} | original sending actor | committed/unknown/expired, original result only within 30 days |
| GET /threads/{id}/messages | after=0, limit=50, optional as_of=sequence | ordered items, as_of_sequence, next_after, read watermarks |
| PUT /threads/{id}/read | `{ "through_sequence": 3 }` | monotone participant watermark; future sequence rejected |
| DELETE /threads/{id}/consent | patient only | closed, repeat safe; available after expiry/policy change |

Bearer auth and current stored role apply. 401 missing/invalid session; 403 expired,
revoked, withdrawn consent or prohibited role; 404 absent/foreign thread; 409
different content on same actor/thread/key or reopening withdrawn enrollment;
410 expired replay; 422 invalid/duplicate/missing key or invalid cursor/body;
503 commit unconfirmed: reconcile original attempt, then retry same key/body.
Keys use 16–128 ASCII letters, digits, underscore/hyphen. Input strips outer
whitespace before binding. Unknown does not prove rejection or durable reservation.
No in-flight/rejected receipt or global exactly-once claim.

Every successful response sets Cache-Control no-store. Content is not audited.
Original message row is the durable receipt; key identity includes thread and
actor, thread binds patient/doctor/original grant. Current original-grant VIEW and
explicit messaging consent are required on every send/read/replay. A new grant
never revives old threads. There is no export, edit, per-message delete, external
delivery or emergency response promise. Body is participant-authored, never a
system diagnosis or clinical clearance.

Frozen sequence high watermark prevents later sends entering subsequent pages.
These cursors are local to the authorized thread; they are not reusable clinical
snapshots. Read status means explicit app acknowledgment, never push delivery.
Content retention is account lifetime; erase either participant's account removes
the entire shared conversation and identifiers from related audit details, also
through the existing deletion-journal replay path. Consent withdrawal retains DB
history but denies its API readback. Legal retention policy remains a product/legal
decision; no regulatory retention certification is claimed.

Migration 20261015_04 follows 03. Populated downgrade refuses data loss.
Amr: preserve key/body across uncertain responses; do not cache private content
after logout or revoked grant; show the emergency-service limitation in the UI.
M1 entry/profile/Home authority, M2 capture/comparison plans, M3 agent boundaries,
M4 product/routine/experiment CAS, M5 notifications and M6 doctor/grants retain
their existing authority contracts. New backend surfaces require Amr's separate
client integration and verification. No Flutter edits.
