# M4 — actionable backend handoff for Hussam

Flutter implemented the existing owned product/routine/adherence/experiment APIs.
No backend, Azure, DB, provider, production or Tester code was changed or called.
All tests use synthetic data. Sources audited: schemas/routine.py, experiments.py,
ProductCreate/Update/Out; api/v1/products.py, routine.py, experiments.py;
services/routine.py and experiments.py; models and October audit reports.

| Priority | Requirement | Current Flutter behavior | Backend acceptance check |
|---|---|---|---|
| P0 | Atomic expected_version / If-Match for PATCH product, entry, draft definition | GET preflight and minimal fields catch known stale edits; strict race guarantee unavailable | Two simultaneous edits against one revision: one succeeds, the other409/412, never silent overwrite |
| P1 | Owner-scoped idempotency key + persisted operation receipt/lookup for product/entry/experiment creation, evaluation and lifecycle transitions | Unknown outcome blocks that operation in the session; GET-only reconciliation, no blind POST retry | Retry same key after committed-but-lost response returns original receipt and no duplicate; different owner cannot retrieve it |
| P1 | Stable cursor/as_of plus completeness metadata for histories | Uses actual offset pages, detects overlap, never infers overall adherence/streaks | Insert while paging retains stable snapshot and exposes incomplete/stale state |
| P1 | Explicit evaluation metric unit/scale/source/algorithm fields | Shows unmodified numeric values as unit unspecified; no %, fraction or clinical interpretation | Manual and legacy image_proxy score domains distinguish capture fraction domains; nulls remain null |
| P1 | Routine server UTC today plus configuration revision/history | Report date is explicit device UTC selection; server validates latest config/start day | UTC midnight/device skew and historical configuration rules return unambiguous eligibility |
| P1 | Explicit clinician authorship/permissions before clinician routine editing | Only source=user_configured cosmetic preferences; no clinician treatment mutation | Read model identifies author/permissions and server denies patient clinical edits |
| P2 | Real relationship IDs and optional catalog provenance | Uses RoutineEntry.product_id and Experiment.routine_entry_id/product_id; marker flags not relationships or verified safety | All referenced IDs owner scoped; verified product metadata carries provenance, no catalog implication from personal record |
| P2 | Timezone-explicit timestamps | Documented existing naive DB timestamps treated as UTC where needed | UTC offset serialized consistently; invalid/unknown timestamps rejected |

Verified correction: RoutineAdherence UNIQUE(routine_entry_id,date,slot) already
exists and commit conflicts return409. Do not implement duplicate uniqueness
again based on a previous assumption. Uniqueness does not replace idempotency
receipt lookup or prove that a lost POST belongs to a specific client attempt.

Retained separate unresolved concerns: B1 report-only observation versus
measurement-based Home/baseline semantics; consent policy version/onboarding
completion read model; future comparison schedules/doctor or authorized AI source;
Agent execution, memory and provider authorization; notification delivery/quiet
hours/M5. Flutter does not fabricate or resolve these through local state.

No request to deploy/create paid resources. Hussam owns implementation and
isolated environment validation; coordinate an approved test contract before live QA.
