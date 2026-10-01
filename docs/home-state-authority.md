# Home metrics authority

Scope: Home dashboard only. Rewards and experiment workflow cleanup remain separate milestones.

## Read and write paths

Before: Home rendered local `experimentDay = 1`, fixed 28-day duration and texture goal;
selected a product independently via `ProductsController.inExperiment`; hid all deltas
behind constant Unavailable tiles; read a mutable local journal filled from startup
history with default 70/20/70 scores. `addJournalEntry` manufactured Good/Stable values.
The check-in card read baseline state, whose today flag only covers unlinked check-ins.

Now: authenticated `GET /api/v1/home` scopes experiments, linked product and check-ins
to the session user. It uses the existing backend experiment projection and frozen
pre-experiment baseline comparison (no stored seeded deltas). Journal includes only
confirmed manual/image_proxy measurements, newest first with an ID tie break, capped
at two. Today's UTC completion includes confirmed linked and unlinked check-ins.
Missing experiment/product/reference, including zero denominators, remains explicit.
Legacy/default/simulated measurements remain stored but are quarantined from Home.

Existing writes remain `POST /checkins`, experiment start/pause and product writes.
Home has no write endpoint or local business derivations. Check-in confirmation
refreshes baseline and Home separately; failed reads never undo a confirmed write or
manufacture success. The old journal helper now requests a server refresh.

## Flutter presentation and lifecycle

`HomeController` validates responses and holds a defensive memory-only snapshot.
Home reads this snapshot exclusively for progress, goal, product, comparisons,
completion and journal. Login/startup, confirmed check-in and Refresh Home load it.
Loading, failed/invalid reads or a UTC date change hide cached facts as unconfirmed;
there is no disk cache or demo fallback. Refresh is available for changes elsewhere.
Generation guards prevent old requests from restoring data after logout, deletion,
disposal or a newer refresh. Session clearing clears Home with existing domains.
Rewards tokens/redemptions and experiment/timeline local state are deferred; Home
no longer reads those local experiment or journal values.

## Verification

Backend tests cover authentication, owner isolation (including product association),
seed quarantine, persisted refresh/reload, linked check-in completion, comparisons,
zero references, paused/completed experiments and database failure.
Flutter tests cover server-only widget facts, refresh/restart, empty state, failure
hiding stale data, malformed/nonfinite responses, HTTP failures and request races.
Existing suites verify auth/session/deletion/products/baseline/context regressions.
