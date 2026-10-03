# Real Azure Blob / Image Infrastructure v1

## Scope and verification boundary

Implementation based on clean main e5d3489d3e9bfa96e0e4ebd2e0f306874b74462f.
Storage only: no new Vision/model calls, notifications, Flutter polish, Arabic/RTL,
release or competition layer. The existing check-in local image proxy remains unchanged;
the capture Measurement Engine still computes from submitted bytes before storage.

Local AZURE_STORAGE_CONNECTION_STRING is blank. Azure CLI is installed, but no cloud
inventory or login was performed; an existing production Storage Account/container has
NOT been confirmed. No Azure resource creation, deployment, production smoke, staging,
commit or push was performed. Mocked end-to-end tests demonstrate backend behavior;
they do not verify durable Azure persistence. Live verification remains a rollout gate.

## Architecture and privacy

Evolve AzureBlobService; reuse azure-storage-blob>=12.23.0 already in requirements.txt.
No new packages or database columns/tables/migrations. Settings still use
AZURE_STORAGE_CONNECTION_STRING and AZURE_STORAGE_CONTAINER (default skin-records).
Remove unused AZURE_BLOB_SAS_EXPIRY_MINUTES; old environment values are ignored by
existing Settings extra=ignore behavior. Connection strings stay in deployment secret
configuration, never DB, API responses, commands printed by the application, or Git.
Malformed configuration is degraded. HTTPS is required. SDK timeouts/retries are bounded.

Application never creates containers. An existing private container is checked before
writes AND reads. Remove public /api/v1/static/uploads entirely. Local files are only
supported for historical cleanup, never new persistence or reads. No SAS is issued.
Disable anonymous access at the Storage Account level too; this is an explicit infra
prerequisite, because a data-plane container probe cannot enforce account policy.
See [Microsoft's anonymous access configuration](https://learn.microsoft.com/en-us/azure/storage/blobs/anonymous-read-access-configure).

DB stores only opaque keys. Authenticated GET /captures/{id}/image and
GET /checkins/{id}/image serve bytes through the backend. Owner reads succeed;
foreign patients get 404. Doctors require their current database role and the existing
Doctor Loop active, unexpired patient grant on EVERY request; pending, expired,
revoked, absent grants return 403. Revocation takes effect on the next request.
Responses use Cache-Control:no-store and X-Content-Type-Options:nosniff. No browser
URL can bypass revocation. Bytes already received by an authorized viewer cannot be
revoked retrospectively; no such claim is made. PNG output is bounded by existing
8 MiB input / 16 MP decode limits; responses currently buffer the normalized image
in backend memory rather than streaming chunks. Legacy owner-namespaced JPEG blobs
can be returned as image/jpeg. Ambiguous flat legacy names are not served.

A second ownership check requires the stored key to begin with the row owner's
skin_photos/{owner}/{owner}_ prefix. Account deletion refuses namespaced foreign
references before any external mutation. Legacy URL-like references are hidden from
image_reference/image_endpoint and refused for reads/deletes; repair them explicitly.
Legacy check-ins with opaque keys have storage=legacy_unverified until verified;
new successful image check-ins carry authoritative image_storage=azure_blob provenance.

## Naming, retries and API contracts

New key: skin_photos/{owner_id}/{owner_id}_{record_uuid}.png.
The original filename never enters the key. PNG re-encoding clears image metadata,
including EXIF/GPS, while preserving decoded RGB pixels. Rejected bytes are discarded.

Capture fingerprint = SHA-256(JSON of source, view, MIME type and SHA-256(raw bytes)).
Capture ID = UUIDv5(NAMESPACE_URL, JSON of capture-v1, owner, operation identity).
Operation identity is Idempotency-Key when present, otherwise the fingerprint.
Check-in image fingerprint = SHA-256(sorted JSON of time_of_day, notes, experiment_id,
validated/deduplicated report, MIME type and SHA-256(raw bytes)).
Check-in ID = UUIDv5(NAMESPACE_URL, JSON of checkin-image-v1, owner, operation identity).
Identity is Idempotency-Key when present, otherwise backend UTC date + fingerprint.
Fingerprints are kept in existing quality / analysis JSON, not a schema migration.

Optional Idempotency-Key header: at most 128 characters. Reuse the SAME key and payload
for retries; a changed payload with that key returns 409. Keys are owner- and endpoint-
scoped. Use a fresh key for a deliberately separate capture of identical bytes.
Without a key, identical captures deduplicate indefinitely; identical image check-ins
deduplicate within their backend UTC day. For retries across midnight use the header.
Manual check-ins retain their prior semantics (this header applies to photo check-ins).
Changing source/view/notes/report, bytes, MIME or operation key means a new operation.
Replays return the original record/measurement and do not re-upload or repeat audits.
Check-in quality validation is still run before replay; no storage write follows replay.

Capture contract preserves storage, image_reference and measurement. Development/test
without configuration retains explicit metadata-only not_persisted behavior so offline
measurement still works. In staging/production an accepted capture with missing storage
configuration returns 503 and no new capture/measurement; rejected metadata still saves.
A development metadata-only capture can be upgraded by resubmitting its original request
once Azure is configured, retaining the original ID and measurement. Old random-ID
historical captures cannot be reconstructed automatically from discarded bytes.

CheckInResponse adds storage, image_reference and image_endpoint. Deprecated
image_sas_url is always null. New image uploads require quality acceptance AND actual
storage success; no local/mock successful persistence. Invalid/rejected images return
415/413/422 as appropriate, with no check-in/blob. Quality/storage outages return 503.
Manual/report-only check-ins remain available without Azure.

/health azure_services.blob_storage changes from a string to a structured object:
provider none|azure_blob, state unconfigured|available|degraded, durable_images boolean.
Available means private container metadata and service properties were reachable, not
verified image upload/read/delete. Available probes also expose probe=
private_container_metadata, end_to_end_verified=false and versioning_policy=
requires_infrastructure_verification. Production/staging unconfigured or any degraded
provider gives top-level status=degraded. Development unconfigured remains healthy
for its explicitly offline workflows. HTTP health still returns 200; monitors must
inspect the JSON status. Other service health labels are outside this milestone.

## Write and failure semantics

1. Authenticate and lock the owner using the existing DB boundary.
2. Validate request, bounded decode, quality acceptance; no rejected image writes.
3. Resolve deterministic identity / replay; validate DB rows and flush.
4. Capture Measurement Engine builds inline before persistence, without blob reread.
   Check-in keeps its existing local proxy and validates resulting values before storage.
5. Upload private normalized PNG to the deterministic key with SDK retry / overwrite.
6. Set canonical storage reference; commit record, capture measurement or check-in audit
   in the same transaction; only then return persisted success.

A failed upload or DB commit returns 503 with DB rollback, never persisted success.
On a possibly completed upload, cleanup reacquires the owner lock after rollback and
checks ALL capture/check-in references. If a concurrent retry committed that key,
cleanup leaves it intact. Otherwise it deletes the possibly uploaded object.
An ambiguous DB commit outcome likewise relies on the reference recheck/history replay.

If DB and/or cleanup remain unavailable, immediate removal cannot be guaranteed across
these independent systems. Log a generic cleanup-pending warning, keep the deterministic
owner namespace, and run reconciliation after recovery. This boundary is explicit:
there is no transactional DB+Blob commit or autonomous job scheduler in this repo.
Before rollout, operational reconciliation MUST be scheduled and failures monitored.
Account deletion also sweeps the complete owner namespace, including unreferenced files.

Operational reconciliation (dedicated DB session; dry-run default):

```powershell
Set-Location 'C:\Users\Hossam\Desktop\Dermaire-Project\backend'
python -m app.tools.reconcile_images
# Only after reviewing candidates and verifying the environment:
python -m app.tools.reconcile_images --apply
```

The command emits counts only, not patient/blob identifiers. Only matching new PNG
names older than at least 24 hours are candidates. It locks the owner, rechecks global
DB references, and deletes only unreferenced objects. Referenced/recent/legacy/unrelated
objects are untouched. Apply requires PostgreSQL; SQLite is development-only and has
no FOR UPDATE concurrency guarantee. Do not run apply against the wrong DB/container.
Do not enable persistent multi-worker image workflows on SQLite. For staging/production,
PostgreSQL owner locks serialize upload/retry, revocation, deletion and reconciliation.

## Delete and retention boundaries

Existing account deletion ordering is retained: lock owner, validate cross-owner links,
delete explicitly referenced captures/check-ins, sweep skin_photos/{owner}/, and commit
DB deletion only after all storage cleanup succeeds. Absent Azure blobs are no-op.
Delete snapshots too; refuse cleanup if blob soft delete or reported versioning is
active, or if historical/deleted/version copies exist. Verify no exact-name copies remain
AFTER deletion as well, protecting against policy changes during deletion. Other errors
propagate, yielding 503 and retained ownership records for retry. DB deletion failure
may leave records whose images were already removed; retry remains safe.

The current data-plane SDK get_service_properties returns blob soft-delete policy but
NOT account versioning or container soft-delete settings. Do not infer that versioning
is disabled from missing fields. Rollout must verify these separately via Azure control
plane. A version_id returned by upload causes failure instead of a persisted-success
claim; it requires infrastructure cleanup before retry. Existing historical versions
are refused rather than falsely claimed erased. See [Azure versioning](https://learn.microsoft.com/en-au/azure/storage/blobs/versioning-overview)
and [soft delete retention](https://learn.microsoft.com/en-gb/azure/storage/blobs/soft-delete-blob-overview).

Keep blob versioning, blob/container soft delete, immutable policies, legal holds,
point-in-time restore, snapshots, replication destinations and independent backups out
of this dedicated namespace unless a separately designed deletion policy accounts for
all copies. Operator verification of those boundaries is mandatory; the app does not
manage Azure policies or independent backups. API deletion confirms observable Blob
cleanup, not physical secure erasure or a legal/compliance guarantee.

There are no individual capture/check-in DELETE endpoints in this repo. None were added;
no existing image deletion flow was bypassed. Future individual deletes must use the
same cleanup boundary and account for Measurement/Doctor Loop references.

No diagnostic/rejected-image retention. Accepted images remain while the owning account
exists, until explicit deletion. No arbitrary image expiry is introduced. There is no
programmatically managed lifecycle policy. Recommended initial policy: do not age-delete
DB-referenced skin_photos objects; run reference-aware orphan reconciliation >=24h old
on a regular schedule. A blanket Azure TTL on this prefix would destroy valid images
and leave stale DB references. Decide retention periods explicitly before later lifecycle
work; changing tiers/backups is not implemented in v1.

## Migration and rollout (requires separate authorization)

1. Inventory the intended existing Storage Account/container and subscription with the
   operator; neither was confirmed by this local session. Provision anything missing
   only after separate explicit approval. Use a dedicated container with Private access;
   disable AllowBlobPublicAccess at account scope, require HTTPS/TLS, and configure network
   reachability from the backend. No public blob CORS/browser access is needed.
2. Verify data protection/versioning/soft delete/immutable policy/restore/backup settings
   and historical copies. Resolve incompatible retention before enabling uploads. Use
   a dedicated account if existing account-wide policies must remain for other workloads.
3. Supply AZURE_STORAGE_CONNECTION_STRING securely to the backend runtime and set
   AZURE_STORAGE_CONTAINER to the existing private container. Current implementation
   reuses Shared Key/connection-string auth; managed identity is deferred. Scope access
   operationally to the intended workload; never put credentials in Flutter or Git.
4. Use PostgreSQL with the existing schema/FK checks; DEBUG=false to avoid SQL parameter
   logging. No migration/backfill is required. Review legacy local uploads/URL references:
   public fallback is removed, no automated import occurs, ambiguous files require an
   ownership-verified manual cleanup/import decision. Historical not_persisted bytes
   are gone and cannot be backfilled. Previously issued SAS can remain valid until expiry
   or key rotation; coordinate invalidation before asserting immediate access revocation.
5. Schedule the orphan reconciler, initially dry-run, then operator-approved apply on the
   same DB/container at a documented regular cadence. Alert on cleanup-pending logs and
   reconciliation failure. This repo creates no job/resource/automation.
6. Deploy only after authorization, check health state=available and private probe. This
   is NOT end-to-end verification. In staging, upload a non-sensitive accepted fixture;
   verify DB opaque key, actual private blob bytes/no EXIF, measurement unchanged, and
   authenticated backend retrieval after backend restart. Confirm anonymous blob URL and
   removed static route fail, foreign user fails, active doctor succeeds, revoked doctor
   fails immediately. Verify rejected photo creates no object, and outage/retry semantics.
7. Check both capture and check-in uploads; submit same Idempotency-Key twice and confirm
   exactly one record/object/audit. Delete a test account; verify Blob list contains no
   owned current/version/deleted/snapshot copies and DB ownership is removed. Repeat
   missing-object deletion. Validate reconciliation with a staged unreferenced test object.
8. Only after these checks record live persistence as verified. Keep prior DB metadata
   honest; do not relabel old captures persisted. Roll back code/config if checks fail;
   preserve private access and storage credentials required for deletion. Disabling
   storage while retained images exist prevents reliable account cleanup.

Flutter is untouched: current UI does not render these image URLs. It may stop showing
legacy image_sas_url-based availability text. Secure image display should later use
image_endpoint plus an Authorization header through the existing API client; plain
Image.network(endpoint) without authentication is insufficient. No Flutter tests/analyze
required for this backend-only milestone. No additional Vision analysis work was added.

## Exact changed files

- backend/.env.example
- backend/app/api/v1/captures.py
- backend/app/api/v1/checkins.py
- backend/app/core/config.py
- backend/app/main.py
- backend/app/schemas/__init__.py
- backend/app/services/account_deletion.py
- backend/app/services/azure_blob.py
- backend/app/services/image_access.py (new)
- backend/app/services/image_reconciliation.py (new)
- backend/app/tools/reconcile_images.py (new)
- backend/tests/test_account_deletion.py
- backend/tests/test_baseline_authority.py
- backend/tests/test_measurement_engine.py
- backend/tests/test_skin_history.py
- backend/tests/test_image_infrastructure.py (new)
- docs/image-infrastructure-v1.md (new)

Existing tests were updated to use quality-accepted fixtures and the private-storage
boundary, assert handled 503 DB failures, preserve deliberate separate-capture measurement
comparisons through fresh idempotency keys, and test historical cleanup without creating
new mock files. New tests cover SDK fake writes/reads/deletes, accepted/rejected paths,
retries/conflicts, DB/upload failure cleanup, committed-retry protection, orphan recovery,
owner/foreign/doctor/revoked/pending/expired access, missing-object account deletion,
health/config/public privacy, EXIF stripping and legacy URL non-disclosure.

## Verification and repository status

Final verification results will be recorded below after the full suite completes.
No Git mutations or deployment performed. Stop at this milestone.

Final local verification: **566 passed**, 90 existing Starlette HTTP_422 deprecation
warnings, 82.86 seconds. This includes **43 new image-infrastructure cases** and
523 previous backend cases (with the boundary adaptations listed above). Full suite
ran from backend with the existing test virtual environment; pytest cache disabled and
basetemp under this chat's work directory. No dependency installation was needed.
`git diff --check` passed. Reconciliation CLI help was verified; no apply was executed.
Flutter tests/analyze were not run because Flutter was untouched.

Final repository: main, HEAD e5d3489d3e9bfa96e0e4ebd2e0f306874b74462f;
12 tracked files modified, 5 new files, exactly the 17 listed above. No staging,
branch creation, commit, push, deployment or Azure mutations.
Ready for code review/commit; live Azure persistence remains unverified.

Exact optional Git commands (provided only, not executed):

```powershell
Set-Location 'C:\Users\Hossam\Desktop\Dermaire-Project'
git switch -c codex/image-infrastructure-v1
git add -- backend/.env.example backend/app/api/v1/captures.py backend/app/api/v1/checkins.py backend/app/core/config.py backend/app/main.py backend/app/schemas/__init__.py backend/app/services/account_deletion.py backend/app/services/azure_blob.py backend/app/services/image_access.py backend/app/services/image_reconciliation.py backend/app/tools/reconcile_images.py backend/tests/test_account_deletion.py backend/tests/test_baseline_authority.py backend/tests/test_measurement_engine.py backend/tests/test_skin_history.py backend/tests/test_image_infrastructure.py docs/image-infrastructure-v1.md
git commit -m "feat: add private Azure image infrastructure and failure-safe persistence"
git push -u origin codex/image-infrastructure-v1
```
