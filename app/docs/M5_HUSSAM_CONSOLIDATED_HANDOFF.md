# M5 — actionable backend handoff for Hussam

Audited registered backend routes, schemas, models, services, dependencies and
tests at bcbd40250e8f4f9ae7cd5e3f8c0372e6683b458b. No live environment probes,
backend modifications or request to deploy/create paid resources. Amr owns Flutter;
Hussam owns backend/provider/device-delivery infrastructure and isolated validation.
These are capability requirements, not proposed endpoints or existing promises.

| Priority | Verified missing capability | Required acceptance evidence |
|---|---|---|
| P0 | Notification ownership/authority/access lifecycle | Patient A cannot read/mutate B records. Explicit patient/account, clinical/doctor/safety versus AI proposal authority. Revocation/deletion denies access and stops dispatch. Deep links require fresh current-account resource authorization. |
| P0 | Privacy-safe payload/retention/erasure | Minimal lock-screen content; no image URL/token/medical details in unreviewed payloads. Document record/device retention and account deletion/revocation behavior. |
| P1 | Notification history/receipts | Stable owned IDs, actual timestamps/status/content type, read/unread mutation with authoritative GET readback; list/detail and absence distinguished from service failure. |
| P1 | Preference persistence and permission separation | Owner-scoped opt-in/purpose, channels, quiet hours/timezone with revision/receipt readback and cancellation on revocation. Safety acceptance is not push opt-in. OS allowed is not registration/delivery. |
| P1 | Device registration/revocation | Scoped install/token ownership, rotation, expiry, unregister across logout/account switching, failure recovery. No cross-account queued dispatch. |
| P1 | Push delivery infrastructure/status | Distinguish requested, provider accepted, delivered only when proved, failed/expired/cancelled. History/receipt contract and isolated provider tests before Flutter adapter. |
| P1 | Scheduling and cancellation | Persisted user-selected time/IANA timezone/DST policy, eligibility, schedule receipt, reschedule/cancel and reconciliation. AM/PM routine grouping is not a clock schedule. |
| P1 | Clinical follow-up authority | Persisted author/role/permissions, patient confirmation if required, revision, purpose and related resources. No AI/client invented dates; no routine-end comparison authorization. |
| P2 | Paging/freshness/observability | Stable ordered cursor/as-of/revision, duplicate/conflict behavior, privacy-safe diagnostics and exact delivery analytics semantics. |

Existing M1–M4/B1/B2 unresolved work stays separate: report-only Home/baseline,
general check-in idempotency/attempt receipts, consent policy/onboarding read model,
comparison timing/doctor or authorized AI contracts, Agent memory/execution and
M4 atomic revision/operation receipts. Do not duplicate RoutineAdherence uniqueness
already present in backend. No client workaround. Additional offline receipts
requirements will be recorded after F4 inspection.
