# M1 remaining contract and rollout dependencies

2026-11-14. Flutter-only handoff; no Backend change or live call was performed.

## Structured observation: existing schema versus remaining product fields

Verified source: backend/app/schemas/__init__.py SafetyDisclosure, CheckInReport,
CheckInCreate/Observation and backend/app/api/v1/checkins.py. Existing Flutter
models/forms cover these supported fields:

- Required overall_change: better/same/worse; Morning/Evening recording context.
- Symptoms: redness/dryness/itching/burning/breakouts/sensitivity/texture.
- Optional routine_status: followed/partial/skipped/not_applicable.
- Optional patient-reported severity/pain: none/mild/moderate/severe.
- Eight nullable boolean Safety disclosures, with unanswered omitted, not false.
- Optional free-text notes up to1500 Unicode characters.

Master Plan §7.1 also describes concern/skin-body location/onset/duration.
There are no separate structured fields for location/onset/duration or an expanded
concern taxonomy in CheckInReport. extra=forbid prevents silently adding fields.
Notes are not a substitute for structured data; Flutter has not serialized hidden
fields into notes or invented clinical scoring.

Hussam + Amr: specify a backward-compatible versioned extension to the existing
check-in/report contract, not a duplicate endpoint. Required decisions/evidence:

1. Approved field names, vocabulary/body-location granularity and supported
   concern coverage. No disease taxonomy is inferred by Flutter.
2. Onset representation and duration units/date precision/timezone; optional/null
   versus explicitly unknown semantics, valid bounds and contradiction rules.
3. Identical owner-scoped readback in POST receipt and GET history, with provenance
   patient_reported and schema version/capability rules for legacy records/clients.
4. Include added values in payload-bound idempotency/reconciliation semantics;
   changed payload with same original key must not be silently replayed.
5. Confirm interaction with Safety/PSM without turning patient severity into a
   diagnosis. Authenticated patient ownership, safety consent, deletion/privacy and
   cross-account denial must remain enforced by Backend.

Once that additive contract is approved and available, Flutter can add optional
typed inputs, validation, readback and uncertainty tests. No migration, endpoint
implementation, deployment or cloud configuration is authorized by this document.

## Policy document and coordinated release

Existing F8 policy integration is on PR7/8. This M1 branch stays stacked on PR9;
it does not copy those unrelated changes or activate their compile-time rollout.
Legacy server-backed safety acceptance/profile hydration remain unchanged.

Amr/owner must supply approved policy content, rendering format, stable HTTPS URL,
digest, effective version and approval record. Hussam must coordinate compatible
Backend metadata/acceptance release; Amr must integrate reviewed F8 code and only
then make an explicitly approved rollout decision. A source receipt does not prove
document approval or deployed compatibility. No new version/URL/hash was invented.

## Existing projections used by this delivery

No API addition is needed for Home priority/UTC expiry/uncertain readback or
clinician visibility. Flutter uses existing GET /home observation_status schema1
with UTC/day/current summaries, /safety and /doctor/review-status doctor-loop-2.0.
Summary and measurement contradictions fail Home closed. Missing legacy additive
status is unavailable, not an incomplete day. Historical clinician notes invite
reading but do not create a current urgent medical state; a parsed current urgent
decision remains visible even when its containing review format is unsupported.

Real Google OAuth, device/native permission behavior, live Backend qualification,
approved policy activation and clinical/production qualification remain separate
release gates. They do not prevent independent Flutter source work above.
