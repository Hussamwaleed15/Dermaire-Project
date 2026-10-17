# F1–F6 integration audit — 2026-10-18

Clean Flutter HEAD ff1dd1359f7126a550cad67c7f99042f41e79b1b. Verified origin
fetch/push https://github.com/Hussamwaleed15/Dermaire-Project.git, main. Fetched and
fast-forwarded to actual remote8ad2ceafced5b1f06ade5a082d4939503d31c687, preserving
Hussam's backend changes. Baseline pub get/analyzer clean;1335 full Flutter tests.
Read AGENTS, M4/M5/M6 handoffs, EXPANDED_FLUTTER_HANDOFF, MASTER_STATUS,
FINAL_REPORT_AR and current registered router/request schemas/services. Historical
'missing' contracts are not current blockers. Backend1137/PG90 are Hussam's reported
isolated verification, not mobile/deployment validation or tests run in this wave.

| Area | Starting status | Current Flutter and tests | Source-verified integration delta |
|---|---|---|---|
| A Authentication/session | Partially integrated | services/api_service, entry/safety_consent_controller; session_lifecycle/safety_consent | /auth/login/google/register/accept-safety, /users/me: versioned policy must override legacy Boolean, preserve owner/generation/old401 guards |
| B Consent/onboarding | Partially integrated | onboarding_screens, account; account_hydration | safety_consent and onboarding.review_state; POST /users/profile-review; completion receipts. New real integration begins in F1 |
| C Home/snapshots | Partially integrated | home_controller, home/patient_home, clinical; home_state_integration | /home, /clinical-snapshot, /doctor/patients/{id}/clinical-snapshot now actual PG RR; add typed snapshot/freshness, no cross-endpoint atomicity claim |
| D Profile/observations | Partially integrated | account, observations; account/observation | /users/skin-profile, /checkins attempt receipts, /captures/{id}/observations: explicit capture link and original-key reconciliation missing |
| E Guided/private capture | Partially integrated | capture/*; guided_capture/private_capture_history/limits | /captures and guarded image reads work; plan-linked capture selection/receipt integration missing |
| F Products/routines | Partially integrated | products/*, routine/*; m4_products/routine | Product/config receipt and revision/If-Match APIs now real; old preflight-only adapter needs protected headers/attempts |
| G Adherence/history | Partially integrated | routine_controller/UI; m4_adherence | Configuration-history signed cursor/calendar-policy/adherence attempts; retain UTC day identity and no guessed historical backfill |
| H Experiments/tracking | Partially integrated | experiments/*; m4_experiments | Actual draft/lifecycle revision/operation receipts; preserve original body/CAS, fetch current state independently |
| I PSM | Partially integrated | psm/*; personal_skin_model | /personal-skin-model deterministic source; newer schema/provenance/freshness need compatibility; never image AI |
| J Doctor grants | Partially integrated | doctor/patient_access, doctor_connection; m6_connections | /doctor/generate-qr now explicit VIEW/EXPORT/consent receipt, claim/access/attempts; obsolete blanket Flutter block needs scoped replacement |
| K Messaging | Missing | Legacy unavailable copy; no repository | /messaging/threads enrollment/list, messages/read/attempts/consent; typed pages, original grant, exact-key recovery and explicit patient consent required |
| L Follow-up plans | UI scaffold only | Free-text clinical notes; m6_clinical_reviews | /clinical-plans create/detail/history/reschedule/acknowledge/cancel/review/attempts; typed IANA/fold/CAS scheduling missing |
| M Inbox/preferences | UI scaffold only | notifications/notification_availability; m5_* | /notifications/history/read/unread/preferences now real; typed private inbox/CAS preferences required, never infer delivery |
| N Devices/reminders | Missing client; Backend unavailable for live push | No push-token/provider plugin or configuration | /notifications/devices and routine-reminders are real; wire settings/consent, no fake registration or native configuration |
| O Comparison plans | UI scaffold only | comparison/* unsupported adapter; comparison_architecture | /clinical-plans comparison/capture/history/evaluation jobs/human signoff; integrate only defined original-authority plan, no arbitrary pair/clinical score |
| P AI Agent | UI scaffold only | agent/* unsupported adapter; agent_readiness | /agent sessions/context/turns/actions/preview/confirm/requests exist; inference unavailable; distinguish request/confirmation/routing/execution/doctor decision |
| Q Offline/idempotency | Partially integrated | recovery_notice/request_failure; m5_offline | Shared exact intent key/body/precondition and attempt lookup needed; unknown not rejection, original receipt not current state |
| R Account/privacy | Partially integrated | generation guards/private images/doctor_view_lifecycle; m5/m6 isolation | Extend every new cursor/list/editor/write to owner/session/original grant and view lifetime; no PHI persistent cache/logs |

Implementation sequence: F1 current policy/profile review + guarded integration
transport/operation identities, F2 consented messaging and clinical plans, F3 inbox/
preferences/reminders, F4 plan-linked comparison, F5 scoped Agent broker, F6 product
integration/concurrency/privacy/navigation hardening. Separate full tested commits.
No planning-only stop. Status documents record actual code, not future predictions.

Outstanding external limits: real push transport/device proof, comparison model
artifact/secure model image loading/clinical validation, genuine Agent model provider.
Future policy text/version publishing before unauthenticated registration needs an
explicit product/server contract; current registration retains the actual legacy
server default rather than inventing a version. Existing terms are not model advice.
