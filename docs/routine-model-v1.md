# Routine Model v1

## Authority and scope

The backend owns routine configuration and adherence. A saved product, its legacy
`in_routine`, `time_of_use`, `frequency_per_week`, notes, or check-in-level generic
routine report does not create an entry or prove use. There is no backfill from
inventory, profile, sensitive context, demo data, local preferences, or AI.
Configuration is explicitly `user_configured`; adherence is explicitly
`user_reported`, not objectively verified exposure. Missing reports remain unknown.
No diagnosis, medical recommendations, treatment claims, causal conclusions,
notifications, experiments, or Personal Skin Model logic changes.

## Configuration contract

Authenticated owner-only `/api/v1/routine/entries` supports GET and POST (201).
`/entries/{id}` supports GET, PATCH and DELETE (204; soft stop). List accepts
optional `active=true/false`, returns all statuses by default. Empty is `[]` only
when a successful database read finds no entries.

- Required on creation: owned active `product_id`, schedule `AM`, `PM` or `BOTH`,
  explicit frequency `daily`, ISO `start_date` (not future).
- Optional: user instructions up to 2,000 characters, independent `am_order` and
  `pm_order` integers 0–100 (default 0). Sequence ties are allowed; consumers sort
  each slot by its order, then created_at and ID. BOTH participates in both slots.
- Output: ID, current product name, configuration, active, end_date, provenance,
  server created_at and updated_at. SQL timestamp columns follow the existing
  repository's UTC convention (timestamps without timezone; interpret as UTC).
- PATCH edits schedule, daily frequency, instructions (null clears), sequence or
  `active=false`. Product and start date are immutable. Null required fields,
  unknown fields, invalid dates/enums/orders and unsupported frequencies are 422.
- Missing/foreign product or entry is 404 without revealing another owner's data;
  inactive product, immutable stopped entry and slot conflicts are 409.

At most one active entry per product per slot. AM and PM entries for the same
product may coexist; BOTH conflicts with either. Nullable unique slot keys enforce
this in the database, including concurrent writes. Owner row locks serialize
routine/adherence writes and product lifecycle with account deletion on PostgreSQL.
SQLite enforces unique constraints but has no row-level FOR UPDATE support.

## Adherence contract

Authenticated GET/POST (201) `/api/v1/routine/adherence` is separate from configuration.
POST requires entry ID, ISO date, slot AM or PM, status completed or skipped;
optional user note/reason up to 2,000 characters. BOTH requires separate slot
reports. Completed means the user reports following that entry in that slot;
skipped means the user explicitly reports not following it. No partial status,
adherence percentages, automatic missed-day generation or inferred use.

Dates use UTC. A report must be within the entry's start date/latest configuration
update day and today, for an active entry and configured slot. Backdating a start
date does not establish earlier configurations. This conservative bound avoids
projecting edited settings into earlier days because v1 does not version entire
configurations. Same-day edits and reports carry exact timestamps and snapshots;
consumers must not infer use happened at created_at or before/after an edit.
created_at is when the server recorded the report, not its claimed use time.

One immutable report per entry/day/slot; duplicates/conflicting retries return 409
rather than overwrite completed with skipped. Refresh after an ambiguous write;
a matching existing report confirms it was recorded. Reports have ID, source,
server timestamp and a JSON snapshot of the full configuration and product name
at report time. Editing/renaming/stopping never rewrites old snapshots, timestamps
or notes. No adherence edit/delete endpoint in v1; erroneous reports cannot be
corrected yet. Consumers must account for this limitation.

GET supports optional owner-checked `routine_entry_id`, limit 1–500 (default 100)
and offset >=0. Sort is date descending, recorded time descending, ID. Full history
is available through pagination, including stopped entries. No automatic history
or analytics from configuration alone. Failed database writes return 503 and are
rolled back; failures are never empty success or local fallback.

## Stop, product lifecycle and account deletion

PATCH active=false or DELETE stops now and sets end_date to the current UTC day;
DELETE is idempotent and retains the entry. The timestamp distinguishes same-day
reports made before stopping. Stopped entries reject new adherence and edits.
Resuming means creating a new entry; prior evidence stays linked to the prior ID.
Future scheduled starts/stops and backdated stops are excluded.

Changing an owned product to inactive/archived stops its active routine entries in
the same transaction; restoration does not resume them. Changing legacy inventory
membership does not change authoritative routine entries. Any product referenced
by a routine entry (even stopped, without reports) cannot be hard-deleted: 409
PRODUCT_HAS_ROUTINE_HISTORY directs the user to archive it. Products without
routine links retain the prior deletion behavior and experiment protection.
Account deletion removes adherence before entries before products/users under the
existing deletion lifecycle; evidence is not retained after account deletion.
Session expiry/revocation/password changes and owner isolation use existing auth.

## Flutter

Products tab links to a minimal My routine screen: server loading, empty, success,
failure/retry, explicit daily configuration/edit/stop, today's completed/skipped
AM/PM reports and the latest 100 reports. UI dates explicitly use UTC; API supports
older permitted dates and optional adherence notes. Writes must return valid
matching server fields and provenance before success is announced. Failed editor
saves retain the draft. Failed reads hide unconfirmed prior routine state. Session
changes clear state and invalidate pending responses; no persistence, seeds,
optimistic canonical writes or local routine fallback. Legacy product usage
preferences are labelled separately and do not establish actual usage.

## Production migration (manual; not applied by this milestone)

Exactly two additive tables: routine_entries and routine_adherence. No existing
columns change and no inventory backfill. The SQL files specify every column,
foreign key, index, unique constraint and enum/order/source/lifecycle CHECK.

- PostgreSQL: `docs/migrations/routine-model-v1-postgresql.sql`
- SQLite: `docs/migrations/routine-model-v1-sqlite.sql`

Apply the matching file once against the actual production database BEFORE the
new backend is deployed. Inspect whether the tables already exist first: these
scripts intentionally fail if already present, rather than conceal schema drift.
They are transactional and preserve existing rows. No configured Alembic workflow
is assumed. Existing create_all creates missing tables on startup, but this is not
proof of a reviewed production migration; it does not alter existing tables.
If startup has already created these tables, compare their schema/constraints to
the SQL instead of rerunning it. Fresh development/test databases use ORM metadata.
PostgreSQL SQL is generated from matching ORM metadata; no live PostgreSQL or Azure
migration/deployment/production smoke test was performed. SQLite upgrade is tested.
Rollback code first; keep additive tables and evidence. Do not drop tables with
user reports as a routine deployment rollback.

## Future consumers and limitations

Personal Skin Model remains unchanged and continues excluding routine. This model
now provides an authoritative input source for a separately scoped integration:
owner-bound IDs, configuration availability, explicitly reported evidence,
provenance, immutable configuration snapshots, UTC dates and timestamps. A future
Experiment Engine must distinguish intention, reported completion, skipped and
unknown, handle configuration changes and never treat this as causal proof.
Daily only; no weekday/custom frequency, partial reports, reminders, timezone
preferences, full configuration revision history or report corrections. No new
milestone is started here.

## Milestone verification and changed files

- Full backend suite: **195 passed**, including **39 Routine Model tests**.
  Existing session/auth/account deletion/PSM/profile/context/product/doctor cases
  passed. 38 Starlette 422 deprecation warnings; no failed tests.
- Full Flutter suite: **104 passed**, including **7 Routine authority tests**.
- Flutter analyze: **No issues found**. git diff --check: **passed**.
  Tests run against local isolated fixtures, no live accounts.
- SQLite additive migration exercised with existing inventory preserved; enforced
  foreign-key deletion tested through the existing account fixtures.
- No Azure deployment or production migration executed. Commit/push status is
  reported separately at completion; no next milestone is started.

Changed files (repository-relative):

1. backend/app/models/__init__.py
2. backend/app/schemas/routine.py
3. backend/app/services/routine.py
4. backend/app/api/v1/routine.py
5. backend/app/api/v1/router.py
6. backend/app/api/v1/products.py
7. backend/app/services/account_deletion.py
8. backend/tests/test_routine_model.py
9. app/lib/routine/routine_controller.dart
10. app/lib/routine/routine_ui.dart
11. app/lib/services/api_service.dart
12. app/lib/products/products_ui.dart
13. app/lib/products/products_controller.dart
14. app/test/routine_authority_test.dart
15. app/test/products_widget_test.dart
16. docs/routine-model-v1.md
17. docs/migrations/routine-model-v1-postgresql.sql
18. docs/migrations/routine-model-v1-sqlite.sql
