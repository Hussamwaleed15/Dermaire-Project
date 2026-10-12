# M3-F1 — Hussam handoff (current supported scope is not blocked)

2026-10-13. Inspected source `a06eedcd80d2dd6dafaac2879951cb890e36cc53`.
Flutter now reads existing GET /personal-skin-model and presents its supported
v2 evidence. No backend/Azure/DB/provider/production edits or live API calls.

## Existing, not missing

PSM v2 route/schema and deterministic rules; explicit findings/evidence IDs/time/
kind/category/ordinal strength/confidence/caveats; source freshness/unknowns;
measurement-1.0 reads/proxies and conservative comparison; structured observations;
baseline/Home; Safety Engine; visible clinician status/decisions; deterministic
experiment evaluations and constrained assistance/chat. No new PSM, capture,
measurement, safety or doctor-read endpoint is requested.

## Genuine contract limitations for subsequent backend work

1. **Nested source schema/version boundaries — P2.** IntegratedSources/summaries
   use dicts; measurements/experiment/routine/profile/doctor source projections
   do not carry an independently validated nested contract version. Formalize the
   actual selected shapes, category/source/status/nullable/time/units/unknown enum
   policy, especially latest vs latest_measured. Preserve current v2 compatibility.
   Flutter declines unsupported optional formats rather than guessing. Tests:
   missing/null fields, future versions, current failure with earlier success,
   no provenance relabeling, no ordinal label→confidence percentage conversion.

2. **Evidence identity/revision/as-of semantics — P2.** Finding references have
   source/id/fields/time, but not a resource revision or immutable snapshot proof.
   Context/profile/adherence sources can be mutable; experiment evaluation is
   frozen and source dictionaries are read in separate queries. Define a source
   completeness/freshness/as-of manifest and whether references point to historical
   facts or current mutable state, with correction/deletion/erasure semantics.
   Do not treat generated_at as proof every source is fresh. Tests: concurrent
   profile/report/context edits, stale captures with newly computed estimates,
   private-current clinician decision and no fallback to old visible history.

3. **Bounded source inventory and coverage — P2.** Several enrichment queries
   retrieve all owned routine logs, experiments/evaluations and image measurements;
   there is no PSM pagination/completeness manifest for those arrays. Define bounded
   summaries/explicit included/omitted counts and owned ordered detail pagination
   where needed. Do not misrepresent a truncated set as complete longitudinal
   knowledge. Client arrays over the supported bound are reported unavailable.
   Routine consistency counts matching rows (not a deduplicated patient adherence
   score); preserve that meaning or define idempotent/unique-day-slot semantics.

4. **Legacy finding units and measurement provenance — P2.** Finding reference/
   recent/threshold values do not return a unit/method schema for every legacy
   tracking score. Current image proxy dictionaries do return fraction_0_to_1,
   method/source/quality/limitations. If numeric legacy findings are to be exposed,
   provide explicit versioned unit/source/region/provenance and eligibility; never
   silently convert them into medical scores or pool them with capture proxies.
   Flutter shows supported statements/evidence but does not guess those units.

## Separate future work, not current PSM promises

The current PSM is deterministic; assistant_layer is explicitly nonauthoritative
and not included. Future authorized AI context retrieval/image analysis requires
separate consent/purpose/retention, owner-scoped evidence retrieval, minimized
payloads and verified model/source capabilities. M3-F1 adds no PSM payload to chat,
no model scheduling/tool action, no provider enablement and no autonomous agent.
Current safety acceptance is not presumed consent for future processing.
Capture↔observation linkage and scheduled comparison/assessment remain the earlier
M2 handoffs; no timestamp/filename/position workaround. Do not require those future
systems to finish before using the current deterministic PSM screen.
