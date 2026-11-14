# M2 external dependencies — actionable handoff

14 November 2026, Flutter-only source review; no request was sent to Hussam and no Backend/provider system changed.

## Existing contracts consumed safely now

- GET /captures?limit=100: authenticated owner metadata; latest receipts ordered (received_at DESC,id DESC), IDs/source/view/quality/storage/provenance; no cursor. The Flutter list includes rejected records without requesting their measurements.
- GET /captures/{capture_id}: fresh authorized owner detail. Never infer image availability from the stored receipt.
- GET /measurements/{capture_id}: existing measurement only, no generation write. Require matching capture_id, algorithm_version measurement-1.0, supported status, timestamp, capture_quality version/decision/fingerprint, both proxy metrics with exact source/method/region/unit/reliability and finite0..1 values only when measured. Preserve reason/meaning/limitations.404 means no recorded measurement;409 means rejected capture cannot be measured; neither is zero.
- GET /captures/{capture_id}/image: authenticated private bytes; no public URLs. Existing plan image path independently rechecks original plan/grant/revision before and after retrieval.
- Existing clinical plans carry patient/doctor/original access identity, revision, baseline/followup IDs and explicit UTC/timezone schedule. Existing evaluation states/jobs/review remain authoritative. New history is account-wide, never a plan association.

## Hussam: coordinated nonproduction compatibility qualification

Confirm deployed contract versions and consent/session gates, owner404/401/403 behavior, measurement-to-quality binding, image no-store semantics, original-grant revocation with plan evidence and separately current evaluation state. Use synthetic accounts/data in an authorized isolated environment. Flutter mocks do not prove deployment compatibility. No production call or deployment requested by this task.

## Hussam + model/clinical owner: genuine comparison remains unavailable

Current capture-quality-1.0 leaves yaw/pitch/occlusion/uneven-lighting unavailable; two saved images and measured proxies do not prove comparability. measurement.compare itself cannot qualify genuine metadata into a comparable result. Future validated method/unit/quality/version/provenance and original plan/context must be explicit, with reasoned not-comparable/unknown states. Actual model artifacts, private transport, method validation and clinician/clinical qualification are separate gates. Keep current inference unavailable; do not invent results or authorize a replacement grant to resurrect old authority.

Required future contract must identify authorized plan/revision, original grant where clinician access is involved, exact baseline/follow-up capture/measurement/method versions, quality evidence and reasoned readiness, job/result revision/provenance and real limitations. Unknown, cancelled, failed and unavailable cannot imply no improvement or safe replay. No new endpoint is demanded or invented here; align with existing durable job infrastructure first.

## Optional Backend enhancement: history beyond latest100

Owner Hussam; product priority Amr. Current M2 has an honest bounded history and does not require a fabricated next-page token. If lifetime traversal is approved, provide an opaque account-scoped stable cursor over receipt order with tie-break IDs, bounded limits, duplicate/boundary/expiry semantics and privacy-safe historical method versions. No date offset or synthetic cursor should be invented in Flutter. Preserve missing/unsupported measurements independently; consider a bounded joined projection to avoid excessive per-capture reads. Current client deliberately reads at most five accepted-capture metrics per explicit batch, with individual timeouts/errors/retry.

## Amr / Salma / mobile qualification

Approve and execute physical Android/iOS camera permissions (including permanent denial/settings), file-provider cancellation, resume/background/account changes, private viewer memory/lease cleanup and narrow large-text accessibility. Host widget tests cannot replace hardware or native privacy verification. Salma owns independent QA sign-off. Formal M2 closure remains pending; this implementation does not authorize rollout, clinical inference or production policy changes.
