# F3 — Inbox, settings and prospective routine reminders

2026-10-18. Inspected actual notifications routes/schemas/service, routine_reminders
service, source authorization and policy withdrawal exceptions. App-only changes.

Patient Profile and verified doctor Workspace open NotificationInboxScreen. Real
inbox/history pages are bounded, privacy filtered by the backend, and cleared
on errors, cover/background, logout/account switch. Count is explicitly unread
**in loaded items**, not a nonexistent total. Read/unread use actual PUT receipts
and fresh readback, with no optimistic saved or delivery label. Categories filter
current items. History shows returned cancellation/job/attempt states without
interpreting a worker/provider acknowledgment as device delivery.

Preferences use GET/PUT revision CAS; exact pending fields/revision remain in
session memory after an uncertain response. Fresh GET can confirm current matching
settings or surface a newer conflicting edit; neither old receipts nor retries
overwrite a newer revision. Explicit same-body retry first rereads revision.
Delete-all uses actual DELETE preferences?expected_revision, also available after
policy loss using only a last verified numeric revision and server withdrawal
receipt. No private settings are shown while acceptance is unavailable.

Each real routine row links to its owned reminder setting. Draft times on an
unconfigured setting are labeled draft. Explicit save consent, enabled state,
IANA zone, AM/PM minute, DST first/second overlap and gap skip use actual contract.
The backend requires active routine + routine category permission. No local
scheduling, UTC adherence relabeling, backfill or guaranteed hosted worker claim.
Turning categories back on does not resurrect canceled reminders.

Plan notifications open current plan detail. Message notifications reference a
message ID; the contract lacks thread ID/deep-link resolution, so the action
honestly opens authorized conversations, not a fabricated thread. Agent detail
navigation remains F5. Reminder notifications open the specific routine setting.

Push: existing backend DisabledPushProvider + no configured mobile token plugin.
No OS permission request/token invention/device registration/provider/native
changes; provider info screen now correctly distinguishes working inbox/settings
from unavailable device delivery. No lock-screen PHI or persisted private cache.

Known contract limit: read/unread endpoints have no CAS/attempt identity; Flutter
serializes UI actions and rereads but cannot prove transport ordering across
other devices or a late server write after timeout. No exactly-once claim.

23 mocked regressions: both roles, pages/count/history, read/unread, malformed
count/delivery, exact CAS before/after loss, newer concurrent settings, 401/403/
404/409/422/503, reminder zone/fold/gap, policy withdrawal, late hide/logout/account
switch and 320px/200% light/dark. Test transports reject non-test HTTP hosts.
Runtime inspection: flutter devices lists macOS only; flutter emulators reports
no emulator sources. No mobile runtime validation claimed, no native edits.
