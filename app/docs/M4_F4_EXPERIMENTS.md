# M4-F4 — controlled experiments and evidence

Source HEAD before phase: d7aa217ae55305b44683d21ac754bc6ffe08454e.
Verdict: supported v2 operations and evidence presentation implemented; PARTIAL
for atomic stale-draft protection, recoverable mutation idempotency and explicit
measurement units unavailable in the current wire contract.

Inspected experiments routes/schema/model/service, actual coverage/evaluation
logic and existing M3 integration. Owned v2 draft/create/PATCH definition, activate,
finish and evaluate are supported, with by-ID GET and paginated list. Active
experiments freeze previous28 UTC days, exclude incomplete current day from
coverage, enforce one change and server routine locks. No client evaluates evidence.
Legacy records are read-only, not promoted into v2 evidence or measurement data.

Strict remote contract validates owner, engine, lifecycle, real product/entry IDs,
intervention, target7..90, finite coverage and evaluation envelope. Unknown enums,
wrong owner, malformed or nonfinite numbers fail closed. Dates preserve actual
server semantics; the creation date-only payload is correctly matched to the
returned midnight datetime. Draft form uses actual active routine IDs and validates
real field limits; only drafts offer definition editing. It clears on session end.

Create/edit/activate/finish/evaluate require actual receipt and by-ID readback,
then refreshed list before success. Definition/status GET preflight catches known
stale forms. It cannot close an atomic race without backend expected_version.
Uncertain operations remain locked through GET refresh; POST is not blindly replayed.
Pending taps, session changes, reused token generations and old responses cannot
commit into another account. Stop/cancel asks confirmation and preserves history;
it does not restore routine or create a comparison date. List supports offset100
history with overlap detection, no invented completeness or pagination cursor.

UI distinguishes current coverage from saved evaluation. It renders actual label,
strength, summary, limitations, baseline window, source and observation references.
Raw JSON dumps were replaced with readable evidence details. Null values remain
unavailable. Numeric values retain the wire scale; the API lacks explicit unit
metadata, so no percentages, capture-fraction conversions or clinical interpretation
are invented. Results are rule-based association, never causal proof/diagnosis.
No AI-directed changes, photo comparison operations or comparison dates are enabled.

25 new contract/lifecycle/readback/null-value regressions. Existing experiment
fixtures now include actual owner/version identity, hydration and safe auth; old
stale-discard test now asserts explicitly retained stale data. Full analyzer and
full Flutter suite gates recorded in final report. Mocks only; no real-device QA.

Hussam: atomic expected_version on draft PATCH, scoped idempotency/receipt lookup
for create/evaluate/transitions, stable history cursor, explicit per-metric units,
source/scale/algorithm, and reliable clinician authored permissions. Future image
comparison/agent authorization remains separate from experiment lifecycle.
