# M2-F2 — Private Image History & Longitudinal Timeline

Date: 2026-10-13. Implemented supported M2-F2 scope in Flutter only.
Source: clean main `1223cf7ac1504251f40c25bade4472cc8d271d49`, matching
local origin/main and a fresh GitHub main check. Read app/AGENTS.md, M2-F1
implementation/handoff, current capture models/controller/screens/API/session
code, clinical panel, observation entry and actual backend contracts below.
Historical roadmap ideas do not override the current English-only/direct Flutter
or restricted M2-F2 scope. Commit/push identity is in the delivery report.

## Actual contracts inspected

Read-only inspection of backend/app/api/v1/captures.py,
api/v1/measurements.py, services/image_access.py and the existing M2-F1
quality/measurement implementations. No backend files were edited or APIs called.

| GET contract | Actual behavior and Flutter use |
| --- | --- |
| `/api/v1/captures?limit=100` | Current authenticated owner filter; accepted and rejected records; optional state filter not used. Default 50, supported limit 1..100. Orders received_at DESC, id DESC. List only, no cursor/offset/total/has_more/as_of. |
| `/api/v1/captures/{id}` | Owned metadata; missing/unowned 404. No inline measurement in this GET. Detail reads this again instead of trusting a navigation snapshot. |
| `/api/v1/captures/{id}/image` | Authentication required; patient ownership enforced, doctor access separately requires live grant. Missing/unowned/invalid ref/blob missing 404; storage failure 503. JPEG/PNG bytes, Cache-Control no-store, X-Content-Type-Options nosniff. No transferable public/SAS URL. |
| `/api/v1/measurements/{capture_id}` | Owned existing measurement-1.0; 404 absent/unavailable historical estimate, 409 rejected capture. Flutter reads only; no generation POST. |

Capture responses include id, accepted/rejected state, source camera/upload,
front view, received_at with UTC offset, storage azure_blob/not_persisted,
nullable safe image_reference, quality and provenance. Timestamp provenance is
server_received_not_camera_time; source/view are client_reported and quality is
server_computed. API responses do not include user_id; ownership is anchored in
authenticated server filtering plus current session owner. Existing typed M2-F1
DTOs verify safe IDs, owner-scoped storage reference, essential fields, UTC,
state/quality agreement, required quality checks and fingerprint. References are
discarded from DTOs, never opened as network URLs. Malformed/duplicate lists
fail closed, without presenting a partial list as a successful read.

Accepted storage metadata does not prove bytes are currently available.
Rejected captures retain metadata only. Accepted-not-persisted captures can be
read back but have no stored image. The history never invents placeholder photos.

## Architecture and private memory lifecycle

New capture_history_models.dart defines strict history parsing, receipt UTC
presentation, supported recent-set and image limits, typed read errors.
CaptureHistoryRepository uses the existing ApiService. Route-local
CaptureHistoryController and CaptureDetailController bind generation and owner
at creation and gate every result by session, identity, request revision and
route disposal. Concurrent/late refreshes cannot override newer results.
Old snapshots are removed when refreshing, so failures cannot look like fresh
empty or complete history. No history persistence or optimistic insertion.

ApiService adds narrow authenticated list/image methods. Legacy submitCapture,
getCaptureHistory and the separate Tester API/UI remain unchanged. The existing
_SessionClient has a private-image-only streaming branch; all other request
buffering/session behavior is retained. Private requests:

- Use header Bearer authentication and safe capture IDs in the API path only.
- Disable HTTP redirects, never follow public/SAS links or publish credentials.
- Cap encoded bytes at 64 MiB, checking declared length and every received chunk.
- Limit the whole transfer to 20 seconds; close the transport on invalidation
  and after completion/error/timeout. Error bodies are not consumed.
- Current 401 invalidates the session even with a huge/stalled body. Old 401
  cannot invalidate a newer generation, including reused synthetic tokens.

PrivateCaptureImages.shared serializes transfers/decodes across all new routes.
PrivateCaptureImage requests only when its lazy tile is built. Requests queued
for disposed tiles are skipped. ListView uses zero scroll cache extent and no
automatic keepalive; invisible tile disposal releases its decoded lease.

Only JPEG/PNG MIME matching the signature and a single readable frame are
accepted. ImageDescriptor checks source dimensions before frame decode, capped
at 16,000,000 pixels. Longest edge is capped at 256px for thumbnails and 1600px
for detail, without upscaling. Aggregate retained decoded leases are capped at
12,000,000 pixels (about 48 MB RGBA); excess requests report unavailable with
retry rather than keeping unlimited images. A single source transfer/codec may
use additional temporary memory within the encoded/source limits, including
native buffer/decoder copies. These limits are not a claim that process RSS
never exceeds 48 MB or that device performance profiling was performed.

Images are displayed with RawImage and owned ui.Image leases, bypassing Flutter
ImageProvider/ImageCache entirely. No remote image cache entry or disk file is
created. Lease.dispose explicitly disposes pixels; session/account invalidation,
server-revoked acceptance through profile readback, widget replacement/disposal
and store disposal release images. Codecs/descriptors/immutable buffers are
released in finally, including corrupt/late decode failures. Late bytes never
become a lease for a different account. No sensitive logs/analytics were added.
Garbage-collected temporary response buffers are not claimed to be securely
zeroized; no persistent private copies are written.

## Experience, dates and navigation

The existing observation photo entry offers Private image history separately
from observation history. The existing camera/result provides the same route
when not uploading; busy native selection/initialization disables navigation.
Opening history closes camera resources. Native initialization/app-resume cannot
restart a feed behind history. History offers New guided capture, preserving
M2-F1 camera/review/result and unknown-write reconciliation. Returning re-reads
GET history even after an unknown POST; there is no POST retry or inferred row.
A confirmed upload allows history navigation but does not guarantee it appears
in a bounded recent list unless the history GET returns it.

Timeline cards are grouped by real UTC server receipt day, newest first,
with descending actual ID as the tie-breaker matching backend order. Explicit
UTC labeling avoids claiming camera time or a guessed camera timezone. Refresh
replaces records rather than appending duplicates. The UI says most recent
100 capture records and offers no fabricated older pages or total count.

Cards show quality decision, actual client-reported source/front view,
receipt time, lazily retrieved private thumbnail and actual storage metadata.
Tap thumbnail or Open capture details re-reads owned metadata. Detail shows the
private viewer, pinch/pan bounded by InteractiveViewer, visible Zoom in/Zoom out/
Reset image zoom controls, quality version/checks/reasons/limitations and existing
CaptureResult presentation. Image failure is independent of metadata and estimates.
No individual deletion/export/sharing controls were added. Existing Azure/account
erasure disclosures remain truthful.

Estimates remain nonclinical image appearance proxies, never clinical scores or
medical guidance. DTOs bind capture ID, quality fingerprint, algorithm, region,
source, units, nullable value/status and timestamp. Only actual values such as
red_chromaticity_proxy and texture_contrast_proxy, fraction_0_to_1, method version,
computation time and received limitations are shown. Unknown/missing/malformed/
wrong-fingerprint estimates stay unavailable. No zero fallback, severity,
improvement delta, comparison, diagnosis or capture↔observation linkage.

Independent authoritative Safety Engine/clinician panels remain above the image
experience; upload/storage/quality never implies medical clearance or check-in
completion. Home, bottom navigation and report history were not redesigned.
Approved semantic Light/Dark themes are reused. English-only, readable wrapping,
320px/200% text, reduced-motion entry routes and accessible explicit image controls
are covered in widget tests. Loading uses live-region text rather than fake
percent progress; image zoom controls change immediately without extra animation.

## Empty, loading and failures

Only a successful empty history GET shows a confirmed empty state. Loading,
refreshing, timeout/disconnection, malformed contract, authorization, missing
metadata and server failures remain distinguishable from empty history.
Safe GET retry is available. Current 401 clears private session/route state;
403 keeps an honest denied state; 404 photo bytes do not erase a valid receipt;
5xx suggests retry. Corrupt/unsupported/oversized images never paint success.
A not-stored receipt never sends an image GET. Logout, switching accounts,
expiration and late responses clear images/metadata and disable stale navigation.

## Verification

`flutter analyze`: No issues found.
`flutter test`: **703 passed**, including all **619 previous tests** and
**84 new regressions** (76 history/session/widget, 8 image-limit/transport).
All transports use synthetic metadata/accounts/images and the invalid test host;
existing global production-HTTP denial remains enabled. No real patient data,
production/staging API, OAuth, Azure resource, production build/deploy or device
acceptance test was used.

New coverage: success/empty/loading/error/retry, timeout/late/concurrent history,
strict IDs/UTC/day/order/unique recent 100, unconfirmed consent, authenticated
image header/route and no public links, 401/403/404/5xx, old401/reused-token across
history/image/detail/measurements, corrupt/MIME/byte/pixel/aggregate limits,
serialization/disposed queued tiles, lazy thumbnails/cache bypass/disposal,
logout/account switch/revoked consent/idle expiry, metadata-with-missing-image,
verified/missing/wrong-fingerprint estimates, zoom semantics, Light/Dark,
320px/200% and reduced motion, confirmed/unknown camera-return GET without
optimistic insertion or POST repeats, hidden-camera resume suppression.

## Limitations / completion

M2-F2 supported scope is complete. Full historical pagination and server thumbnail
renditions do not exist; this implementation honestly exposes recent 100 only,
downloads full authenticated bytes for visible images, and bounds local decoding.
Revisiting a disposed tile can re-download; no encrypted persistent/offline cache
or public image URL was introduced. Details are previews capped at 1600px,
not full-resolution export. Performance/device QA belongs to the external testing
team; release/profile frame-time and RSS measurements are not claimed.

See M2_F2_HUSSAM_HANDOFF.md for the two genuine scalability capabilities.
No capture read-by-ID or idempotency route is requested: both already exist.
No M2-F3, comparison provenance design, linkage, deletion, backend change or
provider setting was implemented.
