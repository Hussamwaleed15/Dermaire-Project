# M5-F1 — notification availability (PARTIAL)

Starting main/origin/main: bcbd40250e8f4f9ae7cd5e3f8c0372e6683b458b, clean.
Read current app source and M1–M4 reports, including M3 agent readiness and M4
handoff. Audited backend/app/api/v1/router.py and all endpoint modules,
models/__init__.py, schemas, services, tests and dependency manifests. There is
no notification resource, preference, device registration/revocation, token,
history/read receipt, delivery acknowledgement, subscription, opt-in, quiet-hour,
timezone, scheduler/job or cancellation contract. Templates existed only as
Flutter literals, not a backend template service. GET /users/me and
PATCH /users/skin-profile expose no notification preference fields.

Native source inspection only: app/pubspec.yaml/lock contain permission_handler
for existing capture permissions but no push/local notification provider SDK;
Android manifest has no POST_NOTIFICATIONS permission; iOS has no push
entitlement/notification delegate registration. Package.resolved files and all
native configurations remain untouched. No native tools/build/device launched.

Completed: removed six misleading template messages, including unconfirmed
results, interaction and doctor expiry claims, from the existing Profile
notification destination. Relabeled that existing entry as availability (no bell,
feed/badge). A small stateless page explains unavailable sending/scheduling and
preference persistence, unknown/unqueried OS permission and the distinction from
registration/delivery. No toggles, APIs, invented parser, synthetic records,
local preference persistence, permission prompt or new dependency. No patient
state is displayed, so logout/account switch cannot leak notification data.

Real notification preferences/device registration/delivery remain BLOCKED.
Permission denied/allowed/not-determined and confirmed preferences cannot be
observed by the current integration; the app reports unknown, never denied or
allowed. A native adapter purely for tests would not enable the feature and was
not added. Future contextual permission handling needs a real reviewed mechanism
and external device QA. No server consent receipt is invented.

Tests: four new real widget regressions, Light/Dark, 320px, 100/200% text, reduced
motion, readable contrast/accessible labels, no synthetic feed/toggle, zero
permission calls and HTTP. Test transport rejects production host; global HTTP
denial preserved. All existing session/consent tests retained.
Validation: flutter analyze clean; full flutter test passed **1108 tests**
(1104 baseline + 4 new). No production HTTP/native/device validation.
