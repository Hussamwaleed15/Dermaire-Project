# H5/H7 clinician plan contract v1

Prefix `/api/v1/clinical-plans`. All operations authenticated; success no-store.
Actual scheduled plan is separate from existing free-text follow_up notes.

| Method/path | Role and input |
|---|---|
| POST base | doctor: access_id, kind follow_up/comparison, purpose, local_due ISO naive local datetime, timezone IANA, optional fold 0/1, source_type routine/experiment/observation + source_id, baseline_capture_id |
| GET base | patient own/doctor original grants; limit 1..100, after id |
| GET /{id} | same; patient always sees own plan history, even after doctor grant revoked |
| GET /{id}/history | after_revision + limit; immutable revision event snapshots, no numeric AI scores |
| GET /creation-attempts/{patient_id}/{key} | original doctor, reauthorize original grant if committed; unknown otherwise under current patient access |
| GET /{id}/attempts/{operation}/{key} | original actor's committed/unknown/expired result; original doctor grant rechecked |
| POST /{id}/reschedule | doctor, expected_revision + local_due/timezone/fold |
| POST /{id}/acknowledge | patient, expected_revision + consent true |
| POST /{id}/cancel | patient withdrawal or authorized doctor, expected_revision + reason |
| POST /{id}/capture | patient, expected_revision + capture_id |
| POST /{id}/review | doctor, expected_revision + assessment |

All POST operations require exactly one Idempotency-Key (16..128 ASCII identifier).
Attempt binds owner/actor/operation/resource/key/typed payload, including expected
revision. Unknown is not a durable rejection/reservation. Committed replay window
30 days; retained events are immutable account-lifetime history. Replays return
the original snapshot, not current state; GET detail supplies current state.
Foreign404, grant/role403, invalid422, stale revision/state/key conflict409,
expired replay410, commit uncertainty503. Refresh and retry with the same key for
an uncertain outcome; do not generate a new key until reconciliation.

Lifecycle: proposed → patient consent → scheduled → doctor reviewed for follow-up;
comparison requires scheduled → private follow-up captured → doctor reviewed.
Reschedule only proposed/scheduled, resets acknowledgment, returns proposed and
cancels old reminders. Cancel only before reviewed/cancelled. Patient withdrawal
remains available after policy/grant changes. No automatic scheduling at routine
or experiment end. Dates are clinician-authored; no approved AI date proposer is
integrated. Existing H1 provisioned-role and explicit VIEW/EXPORT controls retained.

Comparison requires explicit owner source and baseline; persisted accepted private
captures only. Existing capture upload/quality/storage endpoints supply captures;
plan attachment never accepts external image URLs or another account's capture.
Follow-up capture must differ from baseline and be recorded after acknowledgment.
Early capture is allowed but explicitly marked early in the immutable event;
not an automatic claim of sufficient treatment exposure or clinical validity.
Source identity/revision and recorded/linked time are frozen; full historical
source reconstruction and image-based numerical longitudinal charts are absent.
History supports a revision-axis lifecycle chart; no invented severity/accuracy
values. Event pagination is monotone, not a cross-request atomic snapshot.

Image boundary `comparison-model-boundary-1` always returns unavailable,
validated_model_not_integrated, null model_version/result. Synthetic capture tests
test ownership and lifecycle only, never clinical accuracy. Doctor assessment is
clinician-authored event text and cannot lower or replace the safety engine or
create clinical_clearance. Baseline/follow-up evidence references and event
snapshots remain immutable through later plan changes.

UTC provenance policy uses submitted IANA zone/local wall time/explicit fold;
nonexistent or unspecified ambiguous times rejected. UTC stays fixed during
travel. Patient opt-in creates an inbox/outbox reminder only at acknowledgment;
worker enforces current source revision, original grant and clinician role.
No provider delivery, daemon or host scheduling is claimed.

Migration06 follows05. Populated downgrade refuses data loss. Deleting either
authoring doctor or patient account erases plans/events/receipts and related
notifications under the existing erasure-journal path. This is conservative privacy
behavior, not a clinically approved or legally certified retention policy.
