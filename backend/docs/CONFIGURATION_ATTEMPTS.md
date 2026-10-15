# Routine and experiment committed operation receipts v1

Optional Idempotency-Key is additive; absence preserves existing HTTP and CAS
contracts. Keys use 16..128 ASCII letters/digits/underscore/hyphen. Explicit owner
locks serialize callers. No clinician/grant/external-operation semantics are
inferred by this module: only owner-authored routine and experiment SQL outcomes.

| Domain | Mutations with committed receipts | Lookup |
|---|---|---|
| routine | POST /routine/entries create; PATCH /entries/{id} update; DELETE /entries/{id} stop | GET /routine/configuration-attempts/{create,update,stop}/{key}?resource_id=id |
| experiment | POST /experiments create; PATCH /{id} edit; POST /{id}/activate; POST /{id}/finish; DELETE /{id} cancel; POST /{id}/evaluate; legacy PATCH /{id}/toggle-pause | GET /experiments/operation-attempts/{create,edit,activate,finish,cancel,evaluate,legacy_pause}/{key}?resource_id=id |

All paths use /api/v1. CREATE lookup omits resource_id because its id was unknown
before the response; other operations require the original id. Mutations bind
owner=actor, domain, operation, resource, key, effective typed payload including
explicit field presence, exact If-Match and Routine-If-Match. No equivalence is
invented between different original preconditions or explicit/omitted defaults.
DELETE experiment cancellation has its own identity, separate from POST finish.

Receipt is committed atomically with business rows, routine/product/experiment
side effects, frozen evaluation and minimal audit. Original typed RoutineOut,
ExperimentOut or EvaluationOut is frozen before that commit. Repeating evaluation
with the same key returns the same evaluation identity instead of creating another
result. A new evaluation key still needs the current experiment revision. No
changes to observational algorithms, measurement provenance or clinical authority.

Successful keyed responses include no-store, Operation-Attempt-Id,
Result-Snapshot=original_committed and Operation-Replay true/false. ETag is the
original committed resource revision; evaluation uses Experiment-ETag. A replayed
draft/active configuration is historical output, not a claim about current state;
GET the resource to refresh. Replays do not rerun current business guards or
effects, but current account/session/safety-consent gates still apply.

Lookup returns committed/unknown/expired; source product erasure may yield a
committed receipt with result_availability erased and null result. Foreign owners
see unknown.401 invalid session,422 invalid/duplicate key or invalid operation/
resource scope,409 different payload/preconditions or business conflict,412 stale
new CAS,428 protected missing precondition,410 expired/erased replay,503 uncertain
commit. Reconcile the original key before retrying; unknown does not prove
rejection, missing in-flight work, or exactly-once effects outside SQL.

Routine stop retains history and may record an idempotent already-stopped outcome;
it does not physically delete configuration. V2 experiment definitions remain
immutable after activation; actual multi-resource CAS stays enforced. Legacy
pause remains prohibited for v2. Active experiment routine guard remains intact.

30-day result/replay access; identities retained until account erasure. Product
privacy erasure and offline signed product-journal replay scrub embedded original
product names/configuration even when routine/experiment rows are absent, via
explicit source_product_id; minimal receipts remain. Account deletion erases all
attempts and related audit identifiers. Physical product erase remains blocked
when live routine/experiment dependencies require repair/history preservation.

Migration09 follows08; populated downgrade refuses data loss. No historical
backfill, rejected/in-flight registry, automatic TTL purge, complete routine
configuration event stream or universal historical snapshot is claimed. Legacy
clinical note/review and grant/consent receipts remain separate OPEN domains.
