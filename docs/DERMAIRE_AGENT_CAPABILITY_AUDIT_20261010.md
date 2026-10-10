# DERMAIRE Agent Capability Audit

10 October 2026, Africa/Cairo. Audited source `17f6552b55eee2e8ab87c9019ab1a0a87384662b`, branch main. Read alongside the feature integration report. This is a capability inventory, not permission to expand access or enable providers.

## Current capability boundary

Current AI is **bounded contextual assistance**, not an action agent. POST `/api/v1/assistance` accepts one message and optional narrow task. POST `/api/v1/chat` wraps the same `assist` result. Neither accepts a conversation ID or previous turns. There is no database Chat/Conversation/AgentAction model, backend tool dispatcher, or AI write endpoint in the reviewed routes/models. Availability in the database or clinician timeline is not equivalent to availability in the model's context.

Provider selection receives a minimized fact document and returns validated JSON selecting eligible fact IDs, allowed tracking-gap inference and fixed next-step codes. User free text determines a supported task and precaution/moderation path; **raw question is not sent to the model**. No free-form provider medical prose is rendered. Deterministic templates compose output. `contextual_provider.py:POLICY` explicitly excludes tools/retrieval. Source configuration presence does not prove a provider is available.

## Read and context capability matrix

| Source | Available now / actual fields | Ownership / consent / minimization | Limits and missing context | Proof |
|---|---|---|---|---|
| Profile | skin_type and primary_goals | authenticated user ID; no client-selected owner | No name/email, sensitive demographics, medications, hormonal/cycle fields or notes sent to model. No feature-specific agent-consent record inspected. | `context_builder.py:build_context`, `profile` facts; `api/deps.py:get_current_user` |
| Structured check-ins | overall_change, symptoms, routine_status, structured safety fields; valid manual/image_proxy scores | queries CheckIn.user_id == user.id; excludes simulated/invalid/future | Up to 14 recent rows; no free-text notes or photos; presence is not severity; unknown/stale evidence explicit. | `context_builder.py:recent,report_of,measurement_of` |
| Baseline | status, confirmed days, required days, source check-in IDs, valid metric reference | owner-scoped deterministic reference | First five confirmed metric days; mixed sources do not produce eligible reference metrics. Not report-only or clinical clearance. | `baseline.py:baseline_snapshot`; context baseline_sources |
| Daily context | unusual_conditions, date provenance | owner/date query | 14 rows; mutable snapshots, not edit history; cycle day excluded. Unknown is not false. | `context_builder.py:contexts` |
| Routine | schedule, active, product status, start/end dates, source | entry and product must belong to user | 14 recently updated rows; product/instructions/free text not full inventory knowledge; configuration does not verify use. | `context_builder.py:owned_entries` |
| Adherence | date, AM/PM slot, completed/skipped, routine_entry_id | owner logs with owned entry | 14 logs; missing slots unknown; self-report unverified. Model cannot claim complete longitudinal consistency. | `context_builder.py:RoutineAdherence` |
| Experiments | eligible v2 configuration and latest association label per experiment | owned product/entry required | 14 creation/evaluation rows; bounded statuses/results; no complete frozen result report or free-text intervention history in provider context. | context experiments/seen set |
| Captures/images | accepted captures used to validate Measurement linkage | owned Capture prerequisite | **No image pixels** or visual history supplied to contextual model; no model camera stream; raw capture quality history not a general read tool. | context captures lookup; `image_access.py:image_response` |
| Measurements | availability, valid red_chromaticity_proxy and texture_contrast_proxy | owner + accepted capture + algorithm/unit/provenance check | Up to 14; fraction units, limited image proxies. No inferred hydration/diagnosis; not interchangeable with check-in scores. | context measurement validation |
| Product intelligence | completeness, reported normalized ingredients, evidence, warnings | owner routine_intelligence projection | 14 products/12 ingredients each/12 warnings; omits facts exceeding budget; cannot assure product safety or infer sensitive traits. | `product_intelligence.py:routine_intelligence`; context PI |
| Personal Skin Model | status plus selected changing/stable/association findings | owner deterministic PSM v2 projection | Only selected projection fields enter fact list; the complete PSM v2 source/doctor history is not included. | context `personal_skin_model`, findings[:12] |
| Safety | current evaluated status/reasons/evidence limits | canonical server evaluation before generation | Current guard outranks provider selection; missing risk screen not clearance. | `safety.py:evaluate_safety`; `contextual_ai.py:assist` |
| Clinician decisions | latest patient-visible urgent/doctor_review recommendation can guard output | patient-specific review; visibility checked | Used as precedence gate, not full clinician fact source. No older visible decision fallback if newest is private. Routine notes/review history not part of provider context. | `contextual_ai.py:assist` review query; `test_clinician_assistance.py` |
| Conversation | current message processed to task/precaution; Flutter local list | current auth on request | No previous turns to model/server, conversation store, complete memory, cross-device history or retained consent settings. | `schemas/contextual_ai.py:AssistanceRequest`; `chatbot.dart:messages`; models inventory |
| Home/action context | no direct Home priority/event feed | app reads `/home` separately | Model does not see navigation/UI state, all screens, outstanding tasks, user personalization or absence reason. | context SOURCES excludes Home/events/notifications |
| Clinician workspace | separate authenticated authorized timeline/context on server | `doctor_loop.py:authorize` checks role, active unexpired grant on request | Not a patient-agent permission to access other patients. No doctor-agent tools. | `doctor.py`, `doctor_loop.py:timeline` |

Global bounds: LIMIT=14, MAX_FACTS=240, single value/provenance budget 3000 serialized characters, total value/provenance budget 24000 characters, freshness 14 days (engineering window, not a clinical guarantee). Provider receives included facts; response selects at most 12; deterministic degraded path selects first 8 eligible facts. Availability marks missing/partial/truncated. These bounds explicitly prevent “complete history” claims.

## Action capability matrix

| Action | Existing direct app/backend capability | Executable by AI today? | Required future boundary |
|---|---|---|---|
| Explain recorded changes/routine/tracking/doctor questions | `/assistance` and `/chat`; supported tasks `changes,worsening,tracking,routine,doctor_questions,unsupported` | Read/selection only | Typed citation UI; facts and suggestions labelled by provenance, provider mode and age |
| Recommend next step | Fixed codes record_checkin, record_adherence, review_product_evidence, ask_doctor, seek_guidance rendered as strings | Suggestion only; does not navigate/execute | Separate suggested action with target, authority, expiry and user intent; render current eligibility |
| Save structured observation/context | POST `/checkins`, PUT `/context/{day}` | No | User-confirmed structured draft, owner from token, server validation, idempotency, explicit response/readback; prose never silently becomes medical fact |
| Mark routine slot / change configuration | `/routine/entries`, `/routine/adherence` | No | Confirmed reporting action, snapshot/version and date/slot, conflict handling; preserve unknown use and clinical precedence |
| Create/activate/finish/evaluate experiment | `/experiments` lifecycle | No | User approval for change, authoritative preconditions/constraints and safety status; no autonomous medical intervention |
| Add/update/delete product or ingredients | `/products` for user CRUD; `/admin/product-intelligence/{id}` for admin-only evidence ingestion | No | Preserve evidence provenance and unknown concentrations; never give patient agent admin ingestion rights; confirm destructive changes, journal-aware erasure |
| Upload/read images | `/captures` and authenticated image GET routes | No | Purpose-specific photo consent, byte limits/EXIF stripping, owner authorization, no public URL delegation or provider upload by default |
| Contact doctor / send attachment | No care messaging backend | No | New care conversation/attachment contract, active grant checks, patient-visible medical instructions, privacy and deletion semantics |
| Grant/revoke clinician access | `/doctor/generate-qr`, claim/access/revoke APIs | No | Explicit patient grant/revoke intent, current server readback, separate export scope; AI cannot grant itself access |
| Set notification/personalization preferences | No relevant backend contract | No | User-owned opt-in controls, quiet hours, minimized lock-screen copy and revocation |
| Alter safety/clinician determination | Engine and clinician-authorized routes separately authoritative | **Never** | Prohibit model-originated override and independent intervention; read only canonical result |
| Delete account/images | `/users/me`; no public image-only DELETE | No | Patient explicit destructive action, journal-before-erasure and confirmed completion; no model/background deletion |
| Execute proactively on return | No event scheduler/action planner | No | Refresh authoritative data; ask about absence without inferring why; suggest prioritized reversible actions only |

## Permissions, precedence and memory audit

`get_current_user` checks signed token type/required claims, credential stamp, logout revocation and live account existence. Context reads filter owner in database. Those are meaningful authorization boundaries. They are not granular consent for all future agent tools. `/assistance` uses authenticated current user, not a role-restricted patient dependency, so a doctor token can receive its own context; it does not receive authorized-patient context automatically.

Safety is evaluated before provider invocation. A latest visible clinician recommendation only increases urgency when greater than deterministic status. Urgent/doctor_review guard paths skip the model. Provider output must keep escalation identical to Safety Engine, select eligible IDs, comply with allowed task/step schema and cite allowed inference evidence. Question red flags provide a precaution without writing canonical symptoms. Content Safety is moderation metadata, not a clinical authority. Failure/invalid output returns deterministic evidence with degraded metadata; uncertainty remains explicit.

Current official Flutter chat displays canonical reply/kind but drops structured facts, uncertainty, next steps, clinician provenance and availability. In-memory messages disappear with screen destruction; Clear conversation clears only local display. There is no durable chat deletion/history contract. The chat state lacks an ApiService session-change listener unlike CapturePanel/Timeline; main navigator reset handles normal logout/expiry routes, but late asynchronous responses/session changes still warrant a session-generation regression when expanding chat.

## Separate backend gap tasks for an actual agent

These are proposal tasks; no endpoints are represented as existing merely because a screen intends them.

| Gap | Contract scope and security requirements | Definition of Done |
|---|---|---|
| A1 durable chat | Conversation/turn IDs, ordered cursor pagination, owner-only reads/deletes, consent and retention version, message idempotency; include new records in account erasure and journal restore replay | Restart/cross-device synthetic history, cross-owner denial, retention/deletion tests, no sensitive free-text logs |
| A2 bounded complete context retrieval | Owner-scoped paginated retrieval with source versions/freshness, explicit omission of images/sensitive fields unless purpose-authorized; distinguish full app context from actual bounded provider input | Coverage manifest reports included/excluded sources; revoked/deleted/stale records excluded; budgets and truncation visible |
| A3 tool registry/action broker | Allowlisted typed tools, token-derived owner, least privilege, action scope/expiry, idempotency, preconditions and expected version, server authorization every execution; deny arbitrary URLs/SQL/code | Cross-account/role/consent/expiry/replay/prompt-injection/conflict tests; deterministic safety cannot be downgraded |
| A4 consent/preferences | Account-scoped purpose/version receipts and opt-outs; export consent separated from clinician viewing; provider processing disclosure and data minimization | Revoke stops new processing/actions; projections explain unavailable sources; prior health facts stay authoritative |
| A5 proactive action feed | Durable event/action lifecycle, deduplication, dismiss/snooze/preferences, priority rules with Safety and clinician above routine; deterministic rules before generative copy | Reconnect/return shows current actions without autonomous medical writes; reason/age/action eligibility visible |
| A6 care messaging | Authorized patient/doctor conversations with secured image/report references, role/grant/visibility checks, attachment validation and erasure | Revoked/expired grant denial, readable visible decision continuity, deletion removes new content and references |
| A7 medical action exclusion | Explicit forbidden tool scopes for safety override, prescribing, altering clinician decisions/account permissions, autonomous experiments and deletion | Static registry rejects forbidden classes; adversarial requests cannot invoke hidden write paths; audited user approval receipts for allowed writes |

Build in order: richer safe read presentation first, then consent/history, then explicit user-approved nonmedical actions, then cautious event suggestions. Full physician UX follows patient flow completion. Do not relax the existing constrained provider merely to call the feature an agent.
