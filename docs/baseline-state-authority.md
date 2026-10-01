# Baseline state authority

This milestone covers baseline only. It follows product authority at `a195364`.
Baseline is the foundational divergence: experiment deltas depended on fixed
30/70 references, while Flutter counted all history entries and incremented a
local counter. Report and timeline examples then claimed a completed reference.
Home/context and rewards have other divergence, but neither supplies the
measurement reference experiments need. There is no implemented separate
personal-model store in this repository; its implied inputs are check-in history
and baseline, with report examples currently standing in for real results.

## Read/write map

| Path | Previous authority problem | Current contract |
| --- | --- | --- |
| `User.baseline_checkins_count`, registration, Google signup, internal provisioning | Default/seed of two; not updated by measurement writes | New accounts use zero; column retained for compatibility, ignored by baseline reads |
| `GET /users/me`, `PATCH /users/skin-profile` | Exposed stored counter | Counter projected from confirmed check-ins by the same baseline service |
| `GET /baseline` | No dedicated read | Authenticated owner-only derived snapshot: days, selected IDs, readiness, means, population standard deviations, today's confirmation |
| `POST /checkins` manual measurements | Missing scores became 75/80/20 | Three explicit finite scores in 0–100 required; server records manual provenance after validation |
| `POST /checkins` photo measurements | App sent 72/68/25; image failure generated 75/78/22.5 | App sends no scores; successful image-property processing provides scores with explicit proxy provenance; unavailable analysis is 503 with no row/reward |
| `AzureVisionService` | Simulated success on invalid image; proxy labelled Azure analysis | No fabricated fallback scores; successful values are explicitly local image-property proxies, bounded to 0–100 |
| `GET /checkins` | Journal/history also used as baseline counter | Remains history, including legacy rows; history length is never baseline progress |
| `POST /checkins` experiment update | Fixed redness 30 and texture 70; fake zero/seed changes | Deltas use a confirmed pre-start baseline; absent/zero reference yields null |
| `GET /experiments/current`, experiment creation and pause responses | Persisted seed deltas could leak back | Response projection recomputes comparisons from confirmed linked measurements and pre-start baseline; seed values withheld |
| `DermaireState.loadPreferences` | All check-ins counted; local completion increments | Dedicated baseline refresh; baseline counter/today flag are getters, not mutable state |
| Sign-in `_openApp` | Baseline not reloaded at login | Loads server snapshot independently of product loading |
| `CameraScreen` / `ApiService.submitCheckIn` | Hardcoded scores and local increment after status success | Requires 201 with persisted ID, timestamp, provenance and valid scores; refreshes baseline separately; no local increment |
| `ExperimentTab` | Local wizard step meant started; static 96% consistency; local pause | Begin confirms a server read; real distinct days/readiness/metrics; refresh and unknown/error states; no pretend baseline pause |
| Home check-in card and baseline comparisons | Local today flag; fixed −8%/−12% | Server-confirmed today status or unconfirmed; fabricated comparisons removed |
| `ReportsTab`, results, report, timeline | Static chart/results/first-five claim appeared personal | Explicit demo labels quarantine these examples; they do not consume or establish canonical baseline |
| `clearAccountData`, logout/expiry/deletion | Local health state could survive late responses | Clears snapshot and invalidates pending generations; existing session client rejects responses from another session |

## Server rules

Baseline is a projection of append-only check-in records, not another mutable
table/counter. Select the earliest confirmed unlinked measurement on each of five
different UTC dates, ordered by server creation timestamp then ID. Duplicate
same-day check-ins remain history but advance baseline once. Additional days
cannot change the selected five. Before five days, metrics are unavailable rather
than guessed. Standard deviation is population standard deviation, not a
consistency/safety score.

An experiment reference must have all five measurements before that experiment's
creation timestamp. Later collection cannot repair that experiment retrospectively.
Experiment lifecycle remains separate: this milestone does not start/complete an
experiment, rebase a baseline, or implement reports/context/rewards. An existing
experiment without confirmed pre-start data reports null comparisons. A zero mean
also yields null percentage change rather than division by zero or a fake 0%.

Only new server-validated manual or image-proxy records carry accepted provenance.
Legacy ORM defaults, old analysis output (including simulated fallback), missing
provenance and invalid scores are quarantined from baseline. Existing history is
preserved; it is not retrospectively certified. Legacy users must collect new
confirmed measurements. No database migration or destructive data rewrite is
required: existing columns are nullable, the old counter is ignored and old delta
values are suppressed on reads.

Image-property estimates are self-tracking proxies, not an Azure clinical model or
medical measurements. Manual and proxy values retain provenance in check-in
history; this milestone does not establish clinical validity or context correction.

## Flutter/offline behavior

Flutter holds a session-only presentation snapshot. It has no persisted baseline,
local counter writes, offline success queue or seeded progress. Login/restart
re-reads the backend; existing memory-only authentication still requires sign-in
after a restart. Manual refresh hides current metrics while pending. Failure
shows unknown progress with retry; an earlier snapshot can keep the screen open
but cannot supply current days, readiness, metrics or today's completion.

A confirmed measurement write can succeed while the following baseline read
fails. The completion screen says the check-in was saved but progress could not
be confirmed. Write failure/timeout retains the selected photo and says submission
could not be confirmed; it never navigates to success or increments baseline.
Timeouts may occur after a server commit, so retries can create history duplicates,
but same-day retries never advance baseline twice. Pending reads are discarded on
refresh supersession, account clearing or disposal.

Auth, session, account deletion and products authority retain their existing
contracts. This milestone removes no account records and introduces no secrets.

## Verification

Focused backend tests cover owner isolation, legacy/default quarantine, distinct
dates, stable selected measurements and averages after reload, explicit writes,
missing/out-of-range/non-finite measurements, invalid experiment ownership,
analysis/storage/database failures, actual image proxy processing, pre-start
references, null legacy comparisons and failed reads returning an error.
Flutter tests cover authoritative refresh/restart, empty refresh, stale/pending
reads, account-clear races, malformed reads/writes, score-free photo submission,
and visible unknown/retry UX. Full auth/deletion/products regression suites are run
alongside them; final counts are recorded with this milestone.

Final verification: backend **98 passed**; Flutter **75 passed**; Flutter analyze
**no issues**; `git diff --check` passed. UTF-8 decoding and preservation of
existing non-ASCII text verified; only removed demo percentage arrows and the
replaced baseline-completion comment differ. No secrets or unrelated files were
included. Tests ran with isolated tooling/dependencies outside the repository.
