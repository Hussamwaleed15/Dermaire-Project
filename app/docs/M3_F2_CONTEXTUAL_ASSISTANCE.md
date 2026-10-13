# M3-F2 — Contextual Assistance & Evidence

Source cdabc875ed4c04ff433cd814566921cd5b339bdc, matching fresh main.
Implementation in isolated worktree; original four pre-existing SwiftPM
Package.resolved files preserved. Flutter-only; no provider/backend/prod/Tester edits.

Inspected schemas/contextual_ai.py, api/v1/assistance (/contextual_ai.py), chat.py,
services/contextual_ai.py/context_builder.py, contextual/clinician backend tests,
PSM/clinical source, M3-F1 docs and audits. POST /assistance accepts nonblank
message <=1000 Unicode codepoints and optional allowlisted task. Client sends
message only; no PSM, images, earlier turns or extra health payload. get_current_user
binds owner; client additionally gates confirmed patient consent/current generation.
assist reads records; no db.add/commit or action execution, but provider/moderation
invocation and operational events can recur. Retry is manual once per submitted
question, disclosed as possibly repeating provider request; no automatic retry.

Actual response contextual-ai-1.0/context-1.0: task/message/escalation,
grounded_facts_used, inferred_points, uncertainties, next_steps, authoritative_safety,
nullable authoritative_clinician, provider metadata and moderation metadata.
SourceAvailability, full context, built_at, conversation IDs and durable history
are not serialized. Do not infer source usage from PSM data elsewhere in the app.
Context uses LIMIT14/source, MAX_FACTS240, 3000 chars/fact value+provenance,
24000 total, provider selects <=12 facts; deterministic fallback selects <=8.
These are bounded context selection, not full patient memory.

Added immutable typed assistance/fact/provider/inference/clinician mapping,
finite/bounded JSON value/provenance display and duplicate/missing evidence guards.
Known categories and freshness stay separate; unknown string source identifiers
remain explicitly unknown. Provider grounded claims require configured/invoked/
available/model/provider fields. No fabricated certainty, citations or reasoning trace.

New guarded API preserves legacy requestAssistance/sendChatMessage Tester methods.
Session-bound controller clears question/response on logout/switch/revocation and
rejects late/old401/reused-token data. Loading/errors/unsupported results never
create successful output. No plaintext storage/logs or assistant context expansion.

PSM adds a real Ask about my evidence destination. Shared AssistanceEvidence displays
response snapshot safety/clinician before informational text, separately from current
ClinicalHomePanel. Mode/availability/version, selected facts/JSON values/provenance,
uncertainty and returned next-step text are shown; no step is executed. English UI,
Light/Dark, reduced motion and large text/semantic controls. Server medical prose
is preserved verbatim; current bilingual precaution is a backend limitation, not
local Arabic UI/localization or a translated medical rule.

Verification: flutter analyze no issues; full flutter test **949 passed**, preserving
919 and adding **30**. Synthetic fixtures/mock HTTP only with global production
HTTP denial. Contract/unknown source/provider/evidence/clinical separation, bounded
retry, duplicate sends, errors, timeouts, account/old/current401 and large dark/light
UI covered. Physical device/emulator QA not performed. F2 supported scope complete;
full Agent, future image model, actions, durable memory and streaming unavailable.
