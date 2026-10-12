# M2-F2 — Hussam handoff (scalability; no current supported-scope blocker)

Read-only source inspection on 2026-10-13. Flutter ships current supported
recent history and authenticated images without requiring backend changes.

## 1. Owned history pagination — P2

Current GET /api/v1/captures supports only limit 1..100 with
received_at DESC, id DESC. No cursor/offset/total/has_more exists.
Flutter explicitly shows recent 100 and cannot retrieve older rows.

Define an owner-authorized opaque cursor over (received_at, id), response items
and next_cursor/has_more, with documented stable ordering and insertion/refresh
semantics. Keep current clients compatible. Do not trust client-selected user_id.
Test identical timestamps, unique boundary IDs, concurrent insertions, end of
history, cross-owner/tampered cursors, missing rows and no duplicates across pages.
This enables older history; Flutter will not invent pagination until contracted.

## 2. Authenticated thumbnail rendition — P2

Current GET /api/v1/captures/{id}/image returns complete private JPEG/PNG bytes
with no-store/nosniff; there is no thumbnail/rendition contract. Server stored PNG
can exceed the original 8 MiB upload limit after normalization. Flutter serializes
visible downloads, caps response bytes/source pixels and decodes thumbnails to
256px, but still transfers the complete original for each visible request.

Define an authenticated bounded thumbnail response/rendition option (exact API
shape is backend-owned): same owner/live-grant checks and 404/503 semantics,
no public/SAS URLs, metadata stripped, explicit MIME/pixel/encoded-byte limits,
no-store/nosniff, and optional stable resource revision if agreed. Test unowned,
revoked grant, missing blob, large source, corrupt bytes, limits and no redirect
to a transferable URL. Preserve the existing original-byte route for detail.

Not missing: GET captures list, capture by ID, private image read,
measurement by capture ID, capture Idempotency-Key, account image erasure.
No new individual-image deletion, diagnosis, comparison or sharing is requested.
