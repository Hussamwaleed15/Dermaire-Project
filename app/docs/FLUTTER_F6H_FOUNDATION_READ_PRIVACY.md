# F6h-1 — denied foundation reads

Bounded Flutter-only privacy correction on top of238b5ed.

ProductsController.load, RoutineController.refresh/loadMoreHistory and
ExperimentController.refresh/loadMore previously retained earlier collection
contents after access-denied HTTP403 responses. That is inappropriate once the
current read authorization has been denied. The three collections now discard
cached records and their last-confirmed timestamps on denied/session failures.
Routine configuration and adherence history are discarded together; page controls
are reset. A successful new authorized read can repopulate the collection.

HTTP503/network/timeout remain distinct: previously confirmed data may remain
explicitly stale, with writes guarded. A denial does not discard or re-key any
uncertain mutation: retained original intents remain locked until actual receipt
reconciliation or session termination. Ordinary refresh cannot replace them.
The existing auth transport clears the session on401; generation checks prevent
late successful responses after logout from repopulating any collection.

Files: lib/products/products_controller.dart,
lib/routine/routine_controller.dart, lib/experiments/experiment_controller.dart,
test/wave_foundation_read_privacy_test.dart and
test/m5_offline_recovery_test.dart (the previous403 stale-cache expectation is
replaced with explicit removal and successful fresh authorized-read assertions).

18 new synthetic-host-enforced regressions: each domain401/403/503 plus fresh
recovery, uncertain intent preservation and replacement denial, late read after
logout, both paginated history denial paths, and real ProductsFeatureTab proving
the previously visible product disappears after403.

This is collection/read-cache hardening, not a claim that every editor/route or
all F6 privacy criteria are complete. Broader cross-domain controller/route
lifecycle review, selected grant withdrawal and plan/evaluation policy-loss
withdrawal remain PARTIAL. Restart-safe protected storage and mobile runtime
verification remain BLOCKED; no native/backend/Tester/provider changes or live
requests were made.
