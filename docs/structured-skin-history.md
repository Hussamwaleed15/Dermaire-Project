# Structured skin history v1

Authenticated `POST /api/v1/checkins` remains multipart for existing photo/manual
measurement clients. `report` is a JSON string: `overall_change` (better/same/worse),
`symptoms` (redness/dryness/itching/burning/breakouts/sensitivity/texture), and
optional `routine_status` (followed/partial/skipped/not_applicable). Empty writes,
invalid reports, partial or invalid measurements fail without confirmation.
Report-only events have null measurements; they never advance measurement baseline
or experiment progress. The existing measurement/photo path remains supported.

Events use the server UTC `created_at` as observation/submission time. Backdating
and offline uploads are outside v1. `GET /checkins` returns the authenticated user's
confirmed history newest first, with descending ID as a stable tie break. No local
success or sample events are substituted. Legacy rows without confirmed measurement
provenance are quarantined. Legacy confirmed measurements have null `observation`;
unknown user reports are never backfilled.

`observation` is a versioned JSON envelope with separate `user_reported` and
`provenance`. Manual scores are user-reported, image proxies system-derived, photos
user-uploaded, and timestamps server-recorded. The event ID identifies its inline
measurements; the existing image blob/SAS fields identify its optional photo.
No AI interpretation, causal claims, or experiment engine is added.

The UTC daily-context date always identifies `/context/{date}` for the same user.
An existing context's ID is captured at submission only after owner/date lookup.
Null means no context existed then; context may be recorded later using that date.
Context is mutable and this is a reference, not an immutable context snapshot.
Account deletion removes both owned events (including their JSON) and contexts
through the existing deletion service, along with existing photo cleanup.

## Required deployment step for existing databases

The repository uses `Base.metadata.create_all`, which creates new tables but does
not alter existing tables. There is no configured Alembic migration workflow.
Do not deploy the updated API against an old schema before adding the nullable
column. Back up the database and inspect whether `checkins.observation` already
exists first; apply once during a maintenance window using the normal database
administration process. No production database is changed by this milestone.

PostgreSQL:

```sql
ALTER TABLE checkins ADD COLUMN observation JSON NULL;
```

SQLite (local development):

```sql
ALTER TABLE checkins ADD COLUMN observation JSON NULL;
```

No data backfill is required. Existing score columns are already nullable; model
defaults were removed so a report-only insert cannot fabricate scores. Inspect
any database-specific server defaults and remove them if present (the repository
declared Python-side defaults only). Fresh test databases use the updated metadata.
Rollback the application first; the extra nullable column can safely remain.

Flutter records structured reports with optional photos and displays real history
with loading, empty, failure, and retry states. Baseline/Home measurement semantics
remain unchanged; the timeline is the complete structured evidence view.
