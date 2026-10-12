# M1-F2 — patient Safety Experience and clinician status

## Source / boundary

Base: clean main at `89d59e742b1e7e027797b54231dff5ab5eb2cb3f`, matched local
origin/main and fresh GitHub main before editing. Read app/AGENTS.md, the three
architecture/product/agent/roadmap audits, current Flutter state/Home/profile/
check-in/auth code and actual backend routes/schemas/services/models/tests.
English-only, direct Flutter implementation. No prototype/gallery, backend,
Azure, database, production, AI/provider or separate tester changes/deployment.

## Actual contracts inspected (source, not live production certification)

- `backend/app/api/v1/safety.py`, `schemas/safety.py`, `services/safety.py` and
  `tests/test_safety_engine.py`; `docs/safety-engine-v1.md`.
  GET `/api/v1/safety` uses authenticated get_current_user (not a patient-only
  server role dependency); evidence queries are owned by that user. No owner
  query/body parameter. 200 always computes a SafetyEvaluation, including when
  no current reports exist. Fields: status, engine_version=safety-1.0,
  evaluated_at UTC, reasons[{code,state,summary,evidence}], evidence_status,
  guidance, limitations. No response patient_id, expiry, persisted assessment
  history or atomic revision. Empty/null/malformed body is not a no-risk result.
- Exact statuses: track, low_risk_self_care, doctor_review, urgent. Track and
  low-risk are not clearance. evidence_status.current_report_count,
  risk_screen_complete and stale_or_absent explain missing/incomplete evidence;
  missing/null dictionary entries remain unknown in Flutter, not false.
- `backend/app/api/v1/doctor.py:patient_review_status`,
  `services/doctor_loop.py:review_status,review_out`, schemas/doctor_loop.py,
  models DoctorReviewAction and tests/test_doctor_loop.py; docs/doctor-loop-v2.md.
  GET `/api/v1/doctor/review-status` is authenticated patient-only, own patient
  projection. No patient selector. Fields: schema_version=doctor-loop-2.0,
  patient_id, state, latest_sequence, changed_at/by (nullable), current safety,
  current_decision (nullable), visible history/notes and own grant access.
- Exact review workflows: not_requested (no latest action/live grant), pending,
  in_review, reviewed, follow_up_needed. Workflow is not clinical approval.
  Current action fields: id, sequence, patient_id, doctor_id, access_id, state,
  recommendation (nullable safety vocabulary), rationale (nullable; required
  with a recommendation), patient_visible, created_at, provenance=clinician_authored,
  safety_at_review and divergence/lower/urgent-preserved flags. This increment
  reads current_decision only; never substitutes history/notes for it.
- Latest private action yields null current_decision; an older visible decision
  is not current. Recommendation-null means no recommendation. State/decision
  records persist after grant revoke/expiry; no live doctor presence/deadline is
  inferred. No doctor name or completion date is fabricated. created_at is the
  action record time, not proof that a review completed. DB records are UTC and
  may serialize without offset; naive review timestamps are explicitly parsed
  as UTC. Safety evaluated_at requires an explicit ISO timezone.
- deps.py requires signed access JWT claims/credential stamp, existing account
  and no logged-out/revoked session. Routes can return 401, review role denial
  403, and server errors. Client also guards authenticated patient role and
  owner-matched server safety acceptance. Unsupported field values/formats fail
  honestly; no local permission check substitutes for backend authorization.

## Before / implemented integration

Previously patient Home had no standalone Safety/clinician projection. Chat
could show server guards, while clinician UI existed separately. This increment
adds immutable typed read DTOs, bounded authenticated reads and in-memory
ClinicalController with independent safety/review loading/error/freshness.

Home now starts with a reusable ClinicalHomePanel above routine/experiment
content; main navigation and Home metrics/completion remain intact. It opens a
read-only Safety & clinician guidance screen. Profile offers the same access.
After a confirmed observation the completion view includes the same surface
and triggers new clinical reads without manufacturing baseline/Home progress.
Verified profile changes also refresh guidance because sensitivities/product
information can affect the server evaluation; Flutter never interprets those
health fields as a new clinical result.

Models minimize stored payload: reasons retain code/state/summary; raw evidence
reports, history, notes, grant tokens and names are not copied into clinical UI
state. Arrays are immutable; no local persistence or medical/credential logs.
Review owner, patient_visible/provenance, sequence and state consistency are
verified before a current action can be shown. Invalid/private/foreign decisions
are rejected. Unknown status/engine/schema values remain unsupported, not safe.
Invalid/missing timestamps cannot fabricate record dates; valid UTC dates are
shown as UTC. Existing auth/API unrelated methods and consent/profile controller
logic remain; only new read methods extend ApiService.

## State mapping / precedence

- Server urgent: explicit urgent assessment text/icon, exact server guidance.
- Server doctor_review: clinician-review recommendation text/icon and guidance.
- track: monitoring guidance, never a green all-clear. low_risk_self_care:
  actual low-risk guidance with explicit non-guarantee, never clearance.
- No current reports/stale_or_absent: current symptom assessment unavailable;
  evaluation may still contain authoritative ingredient/history guidance.
  This is not a fictional no_assessment backend status.
- Review state is shown as a server workflow. No visible decision means no
  approval. No recommendation is stated explicitly; clinician rationale/time
  only come from the current patient-visible action.
- Important current clinician follow-up/urgent/review actions appear before
  routine/nonurgent engine guidance. Server-reported urgent engine guidance
  remains prominent before a lower clinician recommendation; divergence flags
  are shown, never used to alter either result.
- /review-status embeds a second Safety Engine evaluation. If it differs from
  the standalone read (or supplies a fresh available read when the standalone
  read is absent/stale), it is separately source-labelled. Urgent embedded
  guidance is prioritized. No fabricated merged/canonical medical status.
  Even a supported raw urgent label with an unknown engine version is visibly
  marked as unsupported urgent server information, not reassuring fallback.
- No generic AI suggestion is inserted into this surface or overrides its
  sources. No fake chat/contact/review actions or simulated clinician messages.

## Loading, failure, stale and session isolation

Both read paths time out after 20s. Initial/independent loading is explicit;
first important engine response renders immediately while review is still
pending. 403/5xx/offline/malformed/timeout are safe messages plus refresh;
401 uses existing session invalidation and drops all health reads. No raw
response/error bodies are displayed or logged by the new integration.

At refresh start, a prior read is labelled previously retrieved/current
unconfirmed; a failed request keeps only that labelled in-memory view. Retrieval
(client) and evaluation/action (server) times remain distinct. Stale clinician
instructions are explicitly described as previous, not current. Refresh never
gates care behind animation or network success. Resume marks memory stale and
rereads; profile readback and confirmed check-in trigger rereads as above.
No arbitrary clinical TTL, expiry or resolution is invented; manual refresh
remains available. There is no background push/automatic expiry contract.

Request revision rejects overlapping/older refresh results. Session generation,
patient-role/accepted-consent guard and existing _SessionClient reject logout,
account switch, expiry and old 401 before an old response can invalidate a new
session (even a reused token). Controller data clear on logout/switch/disposal.
Detail/actions bind to their session; retained refresh callbacks cannot trigger
another account's read. No unprotected health cache was introduced.

## Design / accessibility / English

Reuses the approved light/dark themes and DermaireCard, read-only layout and
native controls. Brand actions remain Burgundy/Rose; clinical red/amber/neutral
roles stay separate. Status text, source labels and icons accompany color.
Urgent/loading/error changes use live-region semantics; urgent information is
not delayed by reveal/success animations. Refresh is indeterminate, no fake
percentage. Reduced Motion removes loading bars and makes limitation expansion
immediate. Normal expansion is 180ms. Long guidance remains scrollable, readable
at 200% without hiding important instructions. All owned UI is English; server
clinician/user content is not translated or rewritten.

## Validation / completion

Verified in the actual Flutter checkout: `flutter analyze` reports no issues;
full `flutter test` reports **388 passed** (321 existing + **67 new**).
No existing regression was removed or weakened. Diff checks pass. Byte comparisons
confirm unchanged consent/profile controller logic, entry motion, tester and
HTTP-denial configuration. No real patient/production API, OAuth, provider or
deployment testing was performed.

New regressions cover actual contract shapes/statuses, null/unknown/invalid values,
privacy/owner/provenance, source priority, initial/partial loading, retries,
stale views, real 20s timeout/late result, 401/403/503/offline, reused-token old
401/logout/switch races, overlapping reads, UTC date validation, themes/large
text/reduced motion/non-color semantics, Home/detail access, resume, profile and
report-only observation readback without fake completion. Existing auth/consent/
profile/history/authority/tester regressions remain. HTTP denial remains in the
suite binding and explicit transports assert flutter-tests.invalid.

## Known boundaries / Hussam

Supported patient Safety and current visible clinician integration passed all
checks; delivery is completed by the verified normal main push; no essential backend route is missing. Nonblocking
contract gaps are detailed in M1_F2_HUSSAM_HANDOFF.md: consistency/freshness,
messaging and existing report-only completion/idempotency. No older notes/history
browser, grant management, clinician workspace redesign, questionnaire, AI agent,
Home/check-in redesign or subsequent milestone is included. No production/live
OAuth/device release verification is claimed.

## Modified files (10)

- `app/lib/clinical/clinical_models.dart`
- `app/lib/clinical/clinical_controller.dart`
- `app/lib/clinical/clinical_ui.dart`
- `app/lib/services/api_service.dart`
- `app/lib/dermaire_state.dart`
- `app/lib/main.dart`
- `app/lib/app_shell.dart`
- `app/test/clinical_status_test.dart`
- `app/docs/M1_F2_SAFETY_EXPERIENCE.md`
- `app/docs/M1_F2_HUSSAM_HANDOFF.md`
