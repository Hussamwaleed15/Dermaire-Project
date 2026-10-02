# Experiment Engine v2

## Scope and authority

The authenticated backend owns definitions, transitions, progress, evidence and
evaluation. Flutter reads and confirms server writes and readbacks. There is no
seeded experiment, local success, client evaluation, medical intervention,
diagnosis, treatment prescription or recommendation. Results describe associations,
never causal certainty. Personal Skin Model v1 is unchanged.

## Lifecycle and API

`draft -> active -> completed | stopped`; `draft -> cancelled`.
Evaluation is independent: an activated active, completed or stopped experiment
can have zero or more append-only evaluation snapshots. Early evaluations return
`insufficient_evidence`. Cancellation before activation cannot evaluate.

Owner-only `/api/v1/experiments`:

- GET lists history (limit 1–200, default 100; offset). GET `/current` returns the
  active experiment or null, including legacy active/paused/baseline conflicts.
- POST creates a draft (201), never starts implicitly.
- GET `/{id}` returns definition, timestamps, coverage and latest evaluation.
- PATCH `/{id}` accepts notes or a complete replacement `definition` while draft.
- POST `/{id}/activate` (200) validates the UTC start date and applies the
  controlled change atomically with activation and evidence freezing.
- POST `/{id}/finish` (200) accepts `completed`, `stopped` or `cancelled`.
  Completing requires the intended complete-day window; early termination uses
  stopped. Drafts can only cancel; activated experiments stop instead of cancel.
- DELETE `/{id}` is a history-preserving cancel/stop transition (200).
- POST `/{id}/evaluate` (201) saves a new structured result. GET `/{id}/results`
  returns evaluation history; existing summaries never change.
- v2 pause is unsupported (409). Legacy pause compatibility remains available
  only for old records. Legacy rows are never upgraded into v2 evidence.

Unknown fields, unsupported types, multiple interventions, null required fields,
invalid dates/durations and malformed schedules receive 422. Foreign/missing
targets receive 404 without disclosure. Lifecycle/configuration conflicts receive
409. Failed commits roll back and return 503 or a constraint-conflict 409.

## Controlled-change rules

Exactly one `intervention` object and one owned routine entry are required. Its
product is derived by the server and ownership is checked separately. Primary
metric is one of hydration, texture or redness. Goal/question is optional user
text (500 characters), notes 2,000; duration 7–90 days. Start is a UTC date, today
or future in draft. Activation requires that exact date to be today. No historical
activation or retroactive attribution.

Supported interventions:

- `start_entry` with schedule AM/PM/BOTH: add an active daily entry through
  Routine v1 on the start day, then activate a start experiment that same day.
  The entry start date and schedule must match. Existing pre-activation reports
  do not establish adherence to the experiment.
- `stop_entry` without a schedule: atomically stops the selected entry, preserving
  its schedule and earlier adherence snapshots.
- `change_schedule` with a different AM/PM/BOTH schedule: atomically changes only
  that field. Existing routine slot uniqueness rules still apply.

Weekly/as-needed frequency changes, medical interventions, changing two products,
routine order experiments, partial adherence and automated recommendations are
excluded. Routine v1 is daily, so schedule is the supported frequency-related
change. One active experiment per user is enforced with a nullable unique
`active_owner` and PostgreSQL owner row locks. Legacy active/paused/baseline rows
block activation until ended. Multiple drafts are allowed.

Routine configuration writes and product edits are blocked while a v2 experiment
is active, preventing a second primary change. To change the routine, stop first.
Experiment termination does **not** restore the prior routine; the user retains
control of subsequent configuration. Deletion/archive after termination cannot
rewrite frozen definitions or past evaluations. Products referenced by experiment
history cannot be hard-deleted; archive instead. Routine DELETE already preserves
entries. Account deletion removes evaluation/check-in/experiment records before
routine/product parents and rejects inconsistent cross-account links.

## Authoritative inputs and provenance

Activation freezes the definition, goal, product reference/name/timestamp, prior
and expected routine configurations, all current routine configurations, disclosed
Profile v2 context and preceding 28 UTC days of confirmed measurements/structured
history and daily context. Baseline evidence is stored with IDs, timestamps,
sources and values. This uses the user's recent history; the separate Baseline
feature's first five confirmed days is unchanged. No population reference is used.

Evaluation consumes owner-only check-ins, actual RoutineAdherence and DailyContext
in the planned window, whether check-ins explicitly link the experiment or not.
Only check-ins recorded after activation qualify. Completed UTC days are counted;
today is incomplete. The window ends at the earlier of intended duration or the
day before termination. Thus mid-day stopping excludes that partial day.
Coverage includes elapsed complete days, distinct observed days, check-in count,
expected-slot adherence coverage, known context coverage and latest check-in time.

Each result freezes the definition, baseline and window source references/values:
check-in IDs/timestamps/metric sources/structured reports, adherence
IDs/dates/slots/status/configuration snapshots and context IDs/values/update times.
Later daily context edits can influence a **new** evaluation, never old results.
All SQL timestamps use the repository's UTC convention without stored timezone.

## Evaluation rules

Rules are deterministic (`experiment_v2_rules_1`), not AI-generated. Minimum:

- Seven complete days since start, five distinct prior days and five distinct
  experiment days with confirmed scores from the same source, covering at least
  half the complete experiment days.
- Latest same-source measurement within three days of the completed window end;
  latest prior measurement within seven days before start. A prior or experiment
  daily score standard deviation above 15 points yields insufficient evidence.
- Manual scores and image proxies are never pooled. The source with the greatest
  minimum prior/window day coverage is selected; ties favor manual.
- Measurements on each day are averaged first, then days weighted equally.
  Legacy/default/unconfirmed values never count. Structured report-only histories
  contribute observed-day/provenance coverage but cannot generate directional
  results in v2.

Adherence requires >=80% expected-slot coverage and >=80% followed expected slots.
Missing reports remain unknown, not inferred completion or non-use. BOTH expects
two reports each complete day. Start/schedule changes expect `completed`.
Stop expects explicitly reported `skipped` use via the existing routine adherence
API; only skipped reports are allowed for a stopped entry linked to an active
stop experiment. Reports must match the frozen schedule, frequency, active state
and product, and be recorded after activation. Generic check-in routine reports
cannot replace target-specific adherence. Partial/skipped generic routine reports
also limit interpretation for use experiments.

Known daily context requires >=70% of complete days with explicit
`unusual_conditions` true/false. A stored empty/unknown context is not coverage.
Unusual conditions on >=30% of complete days, any disclosed unusual baseline
conditions, inconsistent partial/skipped prior routine reports, changed routine configuration, changed/archived target product or
contradictory routine reports yield confounded/low adherence after minimum numeric
evidence is available. Cycle day is preserved as disclosed context without medical
adjustments or inferred explanations. Missing baseline context and unreported
confounders remain limitations; no score correction or day exclusion is fabricated.

The descriptive change is experiment mean minus prior mean for the selected
metric. Threshold is max(5 score points, twice the prior daily population standard
deviation); this is a conservative product rule, **not clinical significance or a
statistical test**. Hydration and texture use higher-is-better scores, redness
lower-is-better. Absolute delta below threshold is no meaningful change. Otherwise
>=80% of day-level directions must agree with the mean. Large changes in both
directions or contradictory structured better/worse reports yield insufficient
evidence, preventing cancellation of inconsistent scores into apparent stability.

Labels:

- `likely_associated_improvement`: directional tracked-score improvement with
  the evidence/adherence/context gates satisfied; association only.
- `likely_associated_worsening`: equivalent observed tracked-score worsening.
- `no_meaningful_change`: differences stay within the descriptive threshold.
- `insufficient_evidence`: early, sparse, stale, source-incompatible or inconsistent.
- `confounded_or_low_adherence`: sufficient numeric history exists but adherence,
  context coverage or other recorded changes prevent interpretation.

Evidence strength is `insufficient`, `limited` or at most `moderate`. Moderate
requires at least ten experiment measurement days, >=90% known context coverage
and manual source in addition to the gates. It is a rule-based evidence description,
not probability, diagnostic confidence or causal certainty. Image proxies remain
limited. Results include summary, comparison window, adherence, confounders,
observed change, coverage, strength, limitations and evaluated/generated timestamp.

## Storage and production migration

Manual migration **required before deployment**; `create_all` cannot add columns.
No production rollout or live writes are part of this milestone.

- `docs/migrations/experiment-engine-v2-postgresql.sql`
- `docs/migrations/experiment-engine-v2-sqlite.sql`

Adds nullable version/reference/intervention/goal/notes/source/activation/stop/
definition snapshot/active owner columns to `experiments`, a unique active-owner
index and reference index. Adds `experiment_evaluations` with result JSON, ownership,
experiment FK, server time and query indexes. PostgreSQL CHECK constraints validate
v2 lifecycle/required references; SQLite upgrades use corresponding triggers
(fresh ORM databases use CHECK constraints). Existing legacy rows retain null
engine version and their history. No backfill, baseline fabrication or status rewrite.

Stop API writes, back up, verify Routine v1 migration is applied, inventory legacy
active/paused/baseline experiments, run the correct SQL once transactionally, then
verify columns/indexes/FKs and legacy row counts before deploying API and Flutter.
SQLite migration is intentionally one-shot and not idempotent. Restore the backup
for rollback; do not drop evidence tables on a live account database. PostgreSQL
migration execution and public production smoke testing remain rollout work.

## UI and boundaries

Existing Experiment and Reports tabs display server history, empty/loading/draft/
active/coverage/insufficient/result/stopped/cancelled/error states. Planning uses an
owned routine target and server-confirmed writes/readbacks. Active experiments link
to the routine reporting UI; stop experiments expose only explicit skipped-use
reporting for their stopped target. The former product experiment toggle is
replaced by guidance to the controlled-change lifecycle; legacy product markers
never create an experiment or count as evidence. Reports expose stored
evidence and limitations, replacing fixed demo results. Session clearing invalidates
pending reads/writes and removes experiment data. Draft core editing is available
via API; the minimal UI can cancel and re-plan. Default UI lists the latest 100
experiments; API pagination provides older history.

SQLite has no owner row lock; uniqueness protects active experiments and routine
slots, but PostgreSQL is the serialized production target. Unreported changes,
objective exposure, photo quality control, midnight race stress testing and causal
inference remain excluded. No automatic completion, notifications or scheduling.

Future PSM may consume stored experiment summaries as qualified observations.
Contextual AI may explain them without upgrading evidence strength. Doctor Loop
may present summaries with consent. None of these consumers, Guided Capture,
Measurement Engine, Product Intelligence expansion or Safety Engine is implemented
or started here.
