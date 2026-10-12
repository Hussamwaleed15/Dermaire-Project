# M2-F3 — Hussam integration handoff

2026-10-13; inspected source `c7f5bd5b44dbb6b02562322cd0abe9495dfb820e`.
Flutter architecture readiness does not require the AI model to be completed.
Real scheduling/association/assessment remains disabled until a verified contract.
No backend, database, Azure, provider or production work was performed.

## Existing supported contract — do not request as missing

Routine entries/adherence; experiment v2 definitions/activation/finish/results and
deterministic evaluations; sequenced clinician reviews including follow_up_needed;
patient-visible review/status and authorized clinician notes (follow_up free text);
captures list/by-ID/Idempotency-Key/private image read; measurement-1.0 proxies and
conservative comparison metadata; deterministic PSM v2; constrained assistance/chat;
Safety Engine/clinician precedence; account image erasure.

These existing evaluations/comparison metadata are not a scheduled AI image
assessment. Neither routine duration/end date, experiment target_days, doctor
note prose nor an assistance next-step string is an authorized comparison plan.
M2-F2 pagination/rendition handoff remains separate.

## Proposed future contract — backend owns schema and endpoints

The items below are contract needs, **not existing JSON fields or route names**.
No speculative endpoints are prescribed. Flutter domain names are provisional;
map/refine them after agreeing the actual wire contract.

1. **Plan persistence and scoped reads.** Owner-authorized plan identity and
   stable lifecycle, effective revision/version, creation/change time, freshness,
   current/superseded relationships, bounded list ordering/pagination and by-ID
   missing semantics. Include new records in account erasure/journal/restore rules.
   Do not expose another patient through client-selected owner, plan or cursor.

2. **Explicit clinical context.** Persist whether a plan relates to a routine,
   experiment, product intervention or authorized follow-up plan, with actual
   owned source IDs and a relationship record. Validate ownership/activity/versions;
   distinguish a reference image from a calibrated medical measurement baseline.
   Routine or experiment completion must not automatically schedule comparison.

3. **Scheduling authority and patient choice.** Distinguish clinician-authored
   decision, AI suggestion and patient confirmation receipts. Link approvals to the
   exact proposal/version, actor and authorization. Return authoritative resolution
   without hiding conflicting source decisions. AI must not overwrite an active
   clinician-directed plan; Flutter will not resolve disagreements. Unknown source
   remains unknown. Define whether clinician plans require confirmation, separately
   from purpose-specific AI image-processing consent.

4. **Time/date semantics.** Canonical timezone-aware instant and original intended
   scheduling timezone/calendar semantics where needed, server evaluated due status,
   evaluation timestamp/freshness and missing/unknown behavior. Server decides
   medical timing case by case; no fixed three weeks or device-time inference.
   Cover DST, timezone changes, rescheduling, grace/expiry and clock skew.

5. **Baseline/follow-up capture association.** Explicit persisted role-specific
   relationship with plan/version, capture identity and authorization proof.
   Validate accepted/stored/available/quality evidence according to the real model;
   define rejected/invalid/missing/deleted image behavior. Upload receipt alone does
   not attach a capture or complete a plan. Never pair oldest/newest/by time/name/
   similarity. Reuse current owner-authorized image routes and safe private storage.

6. **Rescheduling/cancel/expire/supersede.** Versioned transitions and expected
   revision preconditions; define retention/replacement of associations and existing
   assessment records. Return current state on conflict. Old notifications, capture
   contexts and reports must not reactivate an invalidated plan. Define monotonic
   plan/assessment revisions and assessment replacement/supersession semantics;
   client watermarks do not establish server authority or survive restart.

7. **Assessment request/job/status/result.** Explicit plan and evidence identities,
   accepted-request acknowledgement, lifecycle, job/result identity and current-result
   selection. Pending/processing/failed/unavailable/insufficient evidence/unknown are
   distinct from successful results. Specify safe polling/retry and lost-write
   reconciliation before exposing writes. No AI-model simulation while unavailable.

8. **Provenance, uncertainty and review.** Actual source/model/algorithm/version,
   generation time, evidence/capture IDs, data-quality limits, unknowns and evidence
   insufficiency; preserve nonclinical model observation vs clinician-authored
   statement and real clinician review record. Schema/units/capabilities must follow
   the actual model, not an invented improvement percentage, diagnosis, confidence
   or medical score. Unsupported versions must fail closed or remain unavailable.

9. **Consent/authorization/privacy.** Purpose-specific persisted patient consent for
   future AI image processing, receipt version/status/revocation/expiry and current
   eligibility. Existing safety acceptance is not presumed sufficient. Per-request
   authenticated owner/role/live clinician grant checks; do not grant an AI actor
   clinical authority or broader image access. No public/SAS image URLs, payload
   logs, insecure persisted copies or transfer to an unapproved provider. Define
   erasure of plans/results/model copies and actions after consent/account revocation.

10. **Idempotency/isolation/conflicts.** For every future mutation define owned
    idempotency key/payload/version scope, replay/conflict/retention and queryable
    reconciliation without an automatic POST repeat. Existing capture idempotency
    does not supply plan-association/assessment-request idempotency. Test concurrent
    decisions, account deletion, A/B, stale contexts, missing acknowledgements and
    replay after cancellation; authorization rechecked every execution.

11. **Clinical precedence and notifications.** Preserve canonical Safety Engine
    urgency and current clinician instructions independently of AI suggestions or
    failed assessment. Define server-authoritative due events and reminder identity,
    patient opt-in/channel/device registration, quiet hours/timezone, deduplication,
    cancellation/reschedule/supersession and minimal lock-screen/deep-link payloads.
    A notification is not proof of a current plan; reopening must re-read authorization
    and current revision. Delivery/provider configuration is separate future work;
    no push implementation/resource request is part of this Flutter milestone.

## Contract acceptance tests before enabling the real adapter

Synthetic authorized clinician plan → explicit owned baseline → confirmed
case-specific date/consent → server-reported due → one explicit user capture
upload → separate confirmed association → assessment request/readback → real
status/result/provenance/review. Cover pending AI approval and conflicts with a
clinician plan, unknown source/date/status, DST, invalid/rejected/deleted evidence,
insufficient model evidence, failures, reschedule/cancel/supersede/version race,
old requests/401, cross-owner/role/grant/consent denial, erasure and lost response.

Once agreed, implement a verified wire adapter through existing ApiService,
retain default unsupported behavior for missing capabilities, and then separately
authorize production navigation/capture actions. This document is not approval
to enable providers, deploy, mutate production or start M2-F4.
