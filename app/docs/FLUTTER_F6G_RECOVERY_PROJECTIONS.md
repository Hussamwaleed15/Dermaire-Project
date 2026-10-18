# F6g-1 — Recovered writes refresh the actual patient projections

2026-10-18. Builds on0931bef57bcde05136b2ec975acb30a0b020fa21.

Confirmed product recovery now invokes the same existing projection callback as
normal product writes. Routine configuration/adherence recovery has an explicit
onRecoveryConfirmed callback wired by the existing RoutineScreen to the actual
DermaireState.refreshRoutineContext. Experiment recovery retains its actual
existing callback. Own current resources/history are read first; only resolved,
non-stale outcomes request Home/clinical/related product/experiment reads.
Unknown or failed receipt resolution never triggers a confirmed-write callback.

These reads remain independent server projections, not an atomic client-built
snapshot. No check-in flag, score, baseline count, treatment outcome or PSM fact is
incremented locally. A failed Home GET remains unavailable even when the product
request was separately confirmed. Saved original receipt and current view failure
remain different facts.

Intentional local load/refresh increments are now tracked through callback await,
catch and finally. The controller stays busy during post-recovery reads, rejects
another submit/recovery, and checks generation/session again before publishing.
Late completion after logout cannot repopulate or mark success in another session.
A callback failure releases busy state and truthfully says the original request
was confirmed but related information could not refresh; no sensitive exception
text appears and no replacement operation identity is fabricated.

The routine pending-report panel also identifies its original UTC day/slot/status,
so changing the reporting-day selector cannot make an old retry appear to submit
the new draft. Original note text is not copied into this summary.

21 new tests: four domains x unknown/busy callback/logout callback/callback failure;
four real Flutter recovery screens cause actual mocked Home and clinical reads;
product-confirmed plus Home503 stays unavailable. Existing controllers, API client,
widgets and source-faithful fixtures are used. Tests assert new read deltas and
no fabricated Today completion. All transports reject production hosts. These are
client integration tests with fake HTTP, not backend or mobile device E2E proof.

Final gate: pub get succeeded; analyzer clean; all1762 Flutter tests passed (+21).
