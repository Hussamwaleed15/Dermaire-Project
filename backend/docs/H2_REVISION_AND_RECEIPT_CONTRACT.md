# H2-F3/F4 implementation contract and uncovered writes

Status: implemented subsets and design/audit boundaries are listed in H2_NEXT_WAVE_STATUS.md. Products now have the tested opt-in revision subset described in H2_NEXT_WAVE_STATUS.md. No routine/experiment expected_version field or generalized receipt table is shipped.

## F3 source and compatibility gate — PARTIAL (Products opt-in subset implemented)

| Resource | Registered mutable paths | Source/side effects | Missing guarantee |
|---|---|---|---|
| Product | POST /products; PATCH, DELETE /products/{id} | api/v1/products.py; PATCH may deactivate routine entries; experiment activation/finish also modify product flags; create/update/delete audit commits separately | implemented for revision_protected products via If-Match; legacy unprotected mode remains explicit |
| Routine | POST /routine/entries; PATCH, DELETE /routine/entries/{id} | api/v1/routine.py, services/routine.py; delete deactivates preserving history; experiment activation modifies entries too | explicit configuration revision and stale CAS |
| Experiment | POST /experiments; PATCH, DELETE /experiments/{id}; POST activate, finish, evaluate; legacy PATCH toggle-pause | api/v1/experiments.py, services/experiments.py; v2 active definition immutable; lifecycle modifies product/entry; evaluation frozen evidence | draft/lifecycle revision and lost-response attempt binding |

Patient owner locks serialize PG transactions but cannot detect stale sequential edits. Existing adherence uniqueness and clinical expected_sequence CAS remain correct separate contracts. Product.updated_at / routine.updated_at are not an all-writer monotonic revision; Experiment.engine_version is an algorithm/schema version, not a resource revision.

Safe implementation must cover every writer, including experiment side effects, not just three PATCH handlers. Add non-null monotonic BIGINT revision default 1 to product/entry/experiment, backfill on isolated migration, expose revision in read DTOs. Every mutation increments revision atomically. Owner and current resource revision must participate in the SQL UPDATE/DELETE predicate; zero affected rows must be owned 404 or stale 412, with no side-effect commit. Lock owner then affected resources in sorted order; reserve all affected revisions before side effects. Roll back the full transaction on any mismatch. Capture old routine configuration in existing adherence history and preserve immutable activated experiment definitions/evaluations.

Versioned mutation contract: expected_version positive strict integer (or strong If-Match quoted decimal); malformed/mismatching body/header 422; missing required precondition 428; stale 412; business conflict 409. Response includes committed revision and ETag. An idempotent attempt replay is checked before current precondition, and returns the original revision/result without reapplying. DELETE requires revision, returns tombstone receipt; GET resource may be 404 while attempt GET confirms committed deletion. Foreign IDs return 404, never another owner's revision.

Compatibility is an explicit gate: keeping old unconditional writes alive can bypass protection offered by a new v2 route. Before enabling strict revisions, choose either coordinated client cutover (legacy mutations return 428 with upgrade contract) or a persisted per-resource opt-in protected mode (explicit enable response explains legacy clients receive 428 for that resource; all old and side-effect writers enforce it). Merely adding optional expected_version and leaving old writes unconditionally accepted is not full lost-update protection. This wave does not silently introduce such a guarantee. No Flutter change or activation is performed.

Required isolated acceptance: two sessions read same version, simultaneous same/different field writes exactly one succeeds; stale sequential edit also denied; update/delete races; experiment activation versus routine edit/product archive; rollback after a reserved version; lost reply + replay before stale check; old client compatibility per chosen mode; ownership/session expiry; migration upgrade/check/downgrade/data preservation on SQLite and PG, bounded timeout/deadlock tests. Product subset is implemented and separately tested; routine/experiment strict revision contracts remain unimplemented. F3 is not COMPLETE.

## F4 exact inventory

| Family | Current receipt/reconciliation | Remaining |
|---|---|---|
| Report/manual checkins | See F2 ledger for implemented owner/key-bound subset | explicit rejected/in-flight durable states and PG gate; GET attempts typed and exact record GET are implemented |
| Photo checkins and captures | Existing deterministic owner/upload fingerprint and resource readback | generalized attempt lookup, expiry and rejected state; do not replace capture behavior |
| Product create/update/delete | Resource GET/revision and AuditLog; PATCH/DELETE now commit audit atomically, create audit remains separate | durable attempt+receipt, atomic create audit; create duplicate names are not attempt identity |
| Routine create/update/deactivate | Resource GET, history preserved | attempt receipt and revision lifecycle |
| Experiment create/draft/lifecycle/evaluate | GET entity/results, frozen evaluation | client attempt identity; repeated evaluate can create a new evaluation |
| Adherence POST | UNIQUE(entry,date,slot), owned history | payload-bound client attempt; uniqueness conflict does not prove same intent |
| Clinical notes/reviews | immutable note, review expected_sequence and patient/grant locks | durable actor/patient/grant-bound attempt lookup; no note edit or replacement CAS |
| Selected/all grant revoke | selected revoke stable receipt in grant GET; H1 consent audit | client attempt for bulk revoke, historical authorization boundary |
| Safety consent / QR consent | policy boolean/time; H1 scoped evidence audit | policy currency separate wave; operation attempt lookup separate from consent evidence |

Implementation-ready cross-domain attempt table: opaque UUID attempt ID; authenticated owner and actor; operation and resource; optional authoritative patient/grant ID; normalized payload hash/version; expected and committed revision; outcome enum; result snapshot with allowlisted fields; server recorded/expiry times. Unique(owner,actor,operation,key_digest), no raw keys/tokens/photo/clinical content in audits. Business write, receipt and audit must share a transaction. Do not create global publicly queryable lookup. GET must reauthorize current identity, resource/patient scope and grant; revocation must not disclose previously visible clinical content via cached result.

State contract: committed only after atomic commit; rejected only if durable rejection proves no mutation; in_flight only from a persisted reservation/lease (not inferred from absence); unknown when absence/transport uncertainty cannot prove failure; expired when retained tombstone knows expiry. Never turn 5xx/404/empty history into not_committed. For durable reservations use lease/token fencing so a retry cannot commit after lease replacement. A crash before commit permits retry only under unique attempt fencing. No exactly-once external side-effect guarantee; outbox/provider reconciliation needed where storage/journals are involved.

Retention: each operation declares replay window, payload/result minimization, expired tombstone window and terminal erasure. Account deletion removes owned attempts, scrubs shared actor/patient links and independently journaled backups. A restore must apply deletion journal before serving receipt GET/replay. QR/export consent audit retention must remain valid for active grants. No broad retention deletion may silently invalidate H1 consent proof.

Expand one family at a time with focused/full tests and migrations; fault injection before/after commit, concurrent key conflicts, changed hash, owner/actor/grant revocation, expiry, erasure, restoration and readback. This contract is not a claim of deployed implementation.
