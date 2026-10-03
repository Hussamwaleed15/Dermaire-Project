# Contextual AI v1

Backend-owned, read-only assistance over current Dermaire records. The model selects
evidence and tracking steps; the backend validates and renders the final response.
No diagnoses, prescriptions, causal conclusions, fabricated facts or medical clearance.

## Architecture and compatibility

1. Existing authenticated `get_current_user` verifies the account, credential stamp,
   access-token type, expiry and session revocation, and holds the owner lock.
2. `assist` evaluates Safety Engine v1 first. `urgent`/`doctor_review` return its exact
   guidance before context building, provider construction or any external invocation.
3. `build_context` reads owner-scoped records and emits `context-1.0`. It uses explicit
   projections and existing deterministic baseline, PSM v1, PI v1 and safety services.
4. Supported tasks may call `ContextualProvider.generate` when independently enabled
   and Azure credentials/deployment are configured. The raw question is never clinical
   evidence and never goes to the provider. Only the supported task and compact context do.
5. The Azure adapter uses the existing OpenAI dependency, JSON mode, a 20-second timeout,
   no retries, and a strict policy plus response schema. No new dependencies are added.
6. The server rejects unknown/stale citations, unsupported inferences/steps, changed
   tasks, any changed safety state, extra fields, duplicate keys, nonfinite JSON,
   malformed JSON, oversized envelopes and incomplete/refused generation.
7. Only exact attributed backend values and fixed conservative text reach users.
   No unchecked model prose is returned. This is a deliberate v1 tradeoff: model-guided
   evidence selection and ordering rather than unrestricted conversational reasoning.

`POST /api/v1/chat` is a compatibility adapter over the same service. It retains
`reply`, `kind`, `escalation_triggered`, `safety_details.authoritative_safety`, and
`azure_model_used`. The complete new response is under
`safety_details.contextual_assistance`. Its model label describes actual usage rather
than claiming GPT success in deterministic mode. Flutter continues to use this endpoint;
network/server failure now displays unavailable context, without local conclusions.
The old `azure_openai.generate_chat_reply` and `SkinAssistantSafety` helpers remain
for compatibility with existing tests, but the active chat path does not invoke them.

## API contract

`POST /api/v1/assistance`, authenticated with the existing bearer access token:

```json
{"message":"Is my routine consistent?","task":"routine"}
```

`message`: nonblank string, 1–1000 characters. `task` is optional and one of
`changes`, `worsening`, `tracking`, `routine`, `doctor_questions`, `unsupported`.
Additional keys (including owner IDs, context, safety or model settings) are rejected.
If omitted, conservative English/Arabic phrase routing chooses a supported operation;
unrecognized questions are narrowed. An explicit task narrows accompanying prose to
that operation and does not authorize answering arbitrary medical questions.

Response fields:

| Field | Meaning |
| --- | --- |
| `schema_version` | `contextual-ai-1.0` |
| `context_version` | `context-1.0` |
| `task`, `message` | Selected operation and backend-rendered answer |
| `grounded_facts_used` | Exact context fact objects selected for the answer |
| `inferred_points` | Separate `ai_inferred` statements, each with evidence IDs |
| `uncertainties` | Unknown/missing/stale/excluded evidence and limitations |
| `next_steps` | Conservative backend-rendered tracking/doctor steps |
| `escalation` | Exact Safety Engine status; AI cannot change it |
| `authoritative_safety` | Complete existing `safety-1.0` response |
| `metadata` | Provider/deployment, configured/invoked flags, availability, mode, safe reason code |

Modes: `grounded_ai`, `degraded`, `safety_guard`, `narrowed`.
Availability: `disabled`, `unconfigured`, `available`, `failed`, `not_invoked`.
`configured` describes credential configuration, not network health. `available`
requires a successful validated response. `model` identifies the requested deployment;
it does not attest the underlying model revision.

Errors: 401 for invalid/expired/revoked/deleted-account sessions; 422 for invalid
request payloads; 503 for authoritative source failures. Provider failures produce
HTTP 200 with explicitly marked deterministic degraded mode and no AI inference.

## Context schema and grounding

`SkinContext` contains `schema_version`, UTC `built_at`, `facts`, `sources`, `unknowns`,
and authoritative `safety`. Each typed fact contains:

```json
{
  "id":"f000",
  "source":"checkin",
  "source_id":"owned-record-id",
  "field":"overall_change",
  "category":"patient_reported",
  "value":"same",
  "recorded_at":"2026-10-03T09:00:00Z",
  "freshness":"fresh",
  "confidence":null,
  "provenance":{"report":"user_reported","created_at":"server_recorded"}
}
```

Fact IDs are request-local citations, not persistent identifiers. `value` is a JSON
value from an explicit source projection; it is never a raw ORM/database dump.
Categories are `patient_reported`, `system_observed`, `deterministic_derived`.
AI inference exists only in the response's separate `ai_inferred` list.
`system_observed` includes stored source-document observations and image proxies;
it does not imply independent medical verification. PI verification/confidence and
last-verification time remain attached and are never upgraded by the model.

| Source | Included projection and limits |
| --- | --- |
| Profile v2 | Disclosed primary goals and skin type; no inferred defaults. Existing user `updated_at` is the available record recency, not a dedicated profile verification timestamp. |
| Check-ins / Skin History | Up to 14 latest eligible structured reports, explicit safety fields, confirmed manual/image-proxy tracking scores. Patient report provenance must match existing schema. Free notes, images and untrusted/simulated/future observations are excluded. |
| Baseline | Existing first-five-distinct-confirmed-days snapshot and owner-scoped evidence references. Historical reference, never clinical clearance. Mixed-source metrics are omitted as incomparable. |
| Daily Context | Up to 14 latest UTC-day `unusual_conditions` disclosures, explicit false preserved; mutable record warning. No weather or hormonal inference. |
| Routine | Up to 14 latest configurations with active state, date range, schedule, owner-checked product status. Configuration does not establish actual use. |
| Adherence | Up to 14 reported completed/skipped slots with owner-checked routine references. Missing slots stay unknown. |
| Experiments | Up to 14 current-owner configurations and latest eligible v2 saved outcomes; strength/version/reference retained. Labels describe associations, not causes. Legacy experiments are excluded. |
| Measurements | Up to 14 rows linked to accepted current-owner captures; explicit availability. Numeric image proxies require measured status, valid method/source/unit/range and accepted quality reference. No clinical interpretation or inferred comparison. |
| Product Intelligence | Active routine products only; documented ingredient evidence, confidence/verification, completeness/unknowns and deterministic cautions. Up to 14 products, 12 ingredients each and 12 warnings. |
| Safety | Current deterministic status/reasons and engine provenance; absolute precedence. |
| Personal Skin Model v1 | Existing deterministic status, sufficiency and up to 12 changing/stable/association findings with rules and original evidence. No v2 work. |

No demographics, hormonal/menstrual fields, cycle day, medications, names, email,
doctor notes, image bytes/URLs, passwords, tokens or free history notes are sent to
the model. Explicit sensitivity disclosures remain available to existing safety/PI
rules; their matching caution provenance may appear in those rule outputs.

Freshness is `fresh` through 14 days, `stale` thereafter, `unknown` without a usable
time, or `historical_reference` for baseline evidence. Daily/adherence freshness uses
the observed UTC date; measurement value freshness uses capture receipt time, not a
late recomputation time. The 14-day cutoff is an engineering convention, not a
validated medical threshold. Provider citations must be fresh or historical baseline
references. Unknown/stale values cannot become current reassurance.

`sources` reports `available`/`partial`/`missing`, included counts and truncation.
Null fields become explicit unknowns, never false/empty negative evidence. Explicit
false remains a fact. Conflicting reports are retained separately, not reconciled by AI.
Context is capped at 240 facts and a 24,000-character value/provenance budget with
3,000 characters per value/provenance item. Additional metadata makes the actual
payload larger; overflow/truncation is disclosed. Existing deterministic services
still scan owner history and PI combinations; this is not an unlimited-scale query redesign.

As part of grounding, the shared baseline eligibility check now excludes simulated
measurements and future records and safely normalizes comparison timestamps. This
keeps baseline and PSM inputs consistent with accepted authoritative evidence.

## Provider contract and fail-safe behavior

Provider JSON selects `task`, up to 12 `fact_ids`, optional `inferred_points`, one to
four allowed `next_steps`, and the unchanged `escalation`. Allowed step codes:
`record_checkin`, `record_adherence`, `review_product_evidence`, `ask_doctor`,
`seek_guidance`. The backend always adds general seek-guidance wording when absent.

The only v1 AI inference is `tracking_gap`, eligible solely for a fresh active routine
with an active owner product and no eligible adherence records, in routine/tracking
tasks. It must cite a selected routine fact. Its wording explicitly says actual use
and consistency are unknown. All new causal, sensitive or clinical inference is rejected.
PSM associations are deterministic-derived facts, never relabeled as AI discoveries.

`CONTEXTUAL_AI_ENABLED=false` by default. Enable only after reviewing outbound data
authorization, provider deployment and retention settings. Azure credentials alone
do not turn generation on. Missing credentials, SDK/HTTP errors, timeouts or invalid
outputs yield marked deterministic summaries based on the same context, never fake AI.
No error content, provider text, prompts or credentials are echoed or logged here.

Safety `urgent` and `doctor_review` always return exact engine guidance first; even
unrecognized questions cannot bypass that branch. `track`/`low_risk_self_care` may
reach the provider only when enabled/configured, and never imply absence of risk.
The existing keyword precaution for concerning question text is retained as a
conditional request warning without an external call or inferred clinical facts.
Canonical `escalation` remains the engine's status. Legacy chat's
`escalation_triggered`/`kind` also signal that precaution; inspect metadata reason
`question_safety_caution` to distinguish it from a canonical safety guard.

## Privacy, migrations and deployment

No schema migration, prompt/response persistence, context cache or new audit rows.
The old chat length/kind audit write is removed to keep this path read-only.
Existing account deletion/session semantics apply unchanged. Owner filters and
owner-checked foreign references prevent context leakage. Ordinary process memory
is request-scoped; external provider retention is governed by the configured Azure
service and must be reviewed before enabling it. Existing request authentication
holds the account lock through provider generation (up to the adapter timeout),
which favors consistent reads but can delay concurrent owner writes.

Rollout later, only after explicit deployment authorization:

1. Review/commit the exact milestone changes and run backend + Flutter checks.
2. Deploy first to staging with `CONTEXTUAL_AI_ENABLED=false`; no migration.
3. Exercise all four Safety Engine states, deterministic degraded mode, auth,
   isolation, invalid payloads and deletion through HTTPS with disposable accounts.
4. Review Azure JSON-mode support, data permissions/retention, credentials/deployment
   and timeout expectations. Enable on staging and exercise validated provider output,
   rejection/failure fallback, and assert no outbound AI calls for guarded responses.
5. After separate production approval, deploy with the flag initially disabled;
   smoke-test before deciding whether to enable provider generation.
6. Disable the flag for immediate generation rollback; revert the milestone for
   full behavior rollback. Do not persist prompts/responses for monitoring.

Limits/deferred: no live-provider/network smoke test in this implementation, no
general free-form medical chatbot, no new clinical validation, coarse English/Arabic
question routing with English canonical summaries (emergency caution bilingual),
bounded history/ingredient projections, no new experiment recomputation, and no
Doctor Loop v2, Personal Skin Model v2, Blob/Vision integration, notifications or UI
polish. Structured API clients can use task explicitly when phrase routing is insufficient.
