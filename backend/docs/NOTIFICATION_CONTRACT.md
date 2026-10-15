# H6 local notification pipeline v1

Registered prefix `/api/v1/notifications`, current bearer session required:

| Method/path | Contract |
|---|---|
| GET /preferences | revision 0, empty enabled_kinds and push false by default |
| PUT /preferences | expected_revision, enabled_kinds `[message,follow_up,comparison,routine]` subset, push_enabled, IANA timezone, quiet_start/end minutes 0..1439 |
| DELETE /preferences?expected_revision=1 | disable all; available after safety-policy change |
| POST /devices | installation_id (16..128 ASCII identifier), token, platform ios/android/web, push_consent true; requires push enabled |
| DELETE /devices/{id} | owner only; clears encrypted token, cancels outstanding jobs |
| GET | limit 1..100, optional before=owned notification id; inbox only due, uncancelled, currently authorized sources |
| PUT /{id}/read | explicit app-read receipt; idempotent read_at; never delivery confirmation |

Example preference body: `{ "expected_revision": 0, "enabled_kinds": ["message"], "push_enabled": true, "timezone": "Africa/Cairo", "quiet_start": 1320, "quiet_end": 420 }`.
All success responses no-store. 401 session invalid/logout, 403 consent/policy,
404 absent/foreign device/notification, 409 preference revision or active-session
token conflict, 422 schema/timezone/cursor errors. Devices bind owner, JWT jti,
credential stamp and JWT expiration. Tokens use authenticated encryption with a
domain-derived application key; key rotation invalidates old registrations and
requires re-registration. No device token appears in HTTP readbacks or logs.
An active old session must revoke registration before a token is reused by another
session/account. Logged-out/expired/credential-invalid old registrations can be
replaced; old jobs recheck session validity before dispatch.

Message commit atomically enqueues the recipient's opted-in inbox item and current
device jobs. Event identity deduplicates owner/kind/source/revision. No opt-in means
no inbox item and no replay backfill after enabling. Device registration creates
future-event subscriptions only. No guaranteed catch-up of historical events.
Follow-up/comparison/routine kinds are reserved typed hooks, not a claim that all
their schedulers are implemented in this milestone.

Internal `dispatch_one` uses PostgreSQL SKIP LOCKED claims, 60-second lease tokens,
lease-expiry fencing, bounded exponential retry delay (up to one hour), cancellation
and current preference/session/source checks. Quiet hours use a half-open local
clock interval, including both repeated DST hours; equal endpoints disable quiet
hours. A deferred job is reevaluated after five UTC minutes. This is conservative
polling, not an exact quiet-hours-end alarm. No worker daemon or hosted scheduler
has been installed or deployed.

Provider boundary defaults to DisabledPushProvider: outcome `unavailable` persists
as provider_unavailable, never sent/delivered. Offline fake acceptance persists
provider_accepted only; even that is not device delivery. Generic provider payload
is exactly `{ "title": "Dermaire", "body": "You have an update" }`; no PHI,
message body, source identifiers or user identity. No live provider integration,
credentials or device validation exists. Actual push delivery is BLOCKED.
An external provider call cannot be atomic with concurrent DB revocation; adapter
support for job idempotency and separate live privacy/device validation is required
before enabling one. No exactly-once external-effect guarantee.

Deleting either conversation participant removes its source-linked notifications
and jobs, even when the inbox belongs to the other account. Deleting an owner also
removes preferences/devices/jobs. Revoked/expired original message grants and
withdrawn messaging consent hide inbox items and cancel dispatch. No unconsented
export. Migration 05 follows messaging 04; populated downgrade refuses data loss.
