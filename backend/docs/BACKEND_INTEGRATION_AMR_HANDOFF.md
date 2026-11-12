# Backend integration handoff for Amr

Date: 2026-11-13 (Africa/Cairo). Integration branch:
`codex/backend-integration-pr1-pr2-pr3`. Contract commit at the first complete
integration pass: `b6265b537f98d6ad40dacf1cf7a65b2e27b1bbb9`.

This is a backend-to-Flutter contract handoff. It does not authorize Flutter
changes, deployment, migration, or Azure configuration changes. PR #4 must not
be merged without green CI and independent approval.

## Exact versioned API surface

The authoritative OpenAPI document is the output of `app.openapi()` at the
commit above. Its measured inventory is **116 paths / 119 component schemas**.
Canonical compact JSON (`sort_keys=True`, separators `,` and `:`) is 197,249
bytes with SHA-256
`82eceeaa43ab0ff81dafe53e9a90bb87e77e5a6fdf1afe8844dd4045c83def7e`.
Generate the exact JSON from that immutable checkout with:

```powershell
Set-Location backend
$env:ENVIRONMENT = "test"
python -c "import json; from app.main import app; print(json.dumps(app.openapi(), sort_keys=True, separators=(',', ':')))"
```

Do not substitute production or staging `/openapi.json`: both environments are
still on an older package (58 paths / 68 schemas in the last live inventory),
and both return 404 for `/health/build` as of this handoff. Therefore the
integrated contract is coded and tested, not deployed.

## B3 safety-policy metadata and acceptance

Before registration or re-acceptance, Flutter reads
`GET /api/v1/auth/safety-policy`. The response adds:

- `required_version`: exact value submitted as `policy_version`;
- `document_status`: `approved` only when URL and SHA-256 are both configured;
- `document.url` and `document.sha256`: immutable policy reference and digest;
- `acceptance_ready`: acceptance UI must remain disabled when false; and
- `enforcement_enabled`: rollout state, never evidence of user acceptance.

Flutter must display the referenced bytes, verify their SHA-256, and submit the
returned version. On 409 it must refetch and redisplay the policy. No approved
policy document is configured by this code change, and enforcement defaults to
off. Enabling it remains a separately authorized environment rollout.

## B4/B5 password reset

- `POST /api/v1/auth/forgot-password` always returns the same generic response;
  the client must not infer whether the account exists.
- `POST /api/v1/auth/reset-password` accepts email, an eight-digit code, and a
  password of 8-128 characters, returning the updated user on success.
- Five wrong guesses invalidate a code. New requests replace older codes.
- Codes expire after 30 minutes, are single-use under PostgreSQL locking, and
  successful password change invalidates earlier access tokens.
- Delivery runs after the generic response. Provider acceptance or failure is
  not exposed to Flutter. No real-email delivery was performed by tests.

## F8 contracts Flutter must preserve

1. Preserve and send `Original-Grant-Id` on every first attempt and retry of
   clinical note/review POSTs. Use a replacement grant only after opening a new
   context; treat 403 as loss of the original authority.
2. Send `Original-Grant-Binding: explicit`; `legacy-current` is migration-only.
3. Page account sessions through `GET /agent/sessions?limit=&before=` and doctor
   requests through `GET /agent/requests?limit=&before=`. Navigate only with the
   returned `patient_ref`.
4. Navigate notifications with `target.thread_id`, not message `source_id`, and
   re-authorize when the target opens.
5. Send notification `state_revision` as `expected_revision`; refresh on 412
   rather than replaying stale device intent.
6. Preserve the evaluation-cancellation `Idempotency-Key` and reconcile through
   `/clinical-plans/{plan_id}/attempts/evaluation_cancel/{key}`. The receipt is
   historical evidence, not current evaluation state.

## Verified versus unavailable

The combined focused safety/reset/readiness suite passed 38 tests. The complete
local suite passed 1071 tests with 97 PostgreSQL-only skips because this
workstation has no disposable PostgreSQL service. PR #4 CI is the required
PostgreSQL 18 zero-skip gate. A green run proves this commit's integration; it
does not prove deployment or production readiness.

The current migration head required by the integrated package remains
`20261024_14`, but the live database revision has not been proven. Agent model
inference, validated comparison inference, clinical AI clearance, and push
delivery remain unavailable or unconfirmed. Flutter must not present diagnosis,
improvement percentages, generated inference, push delivery, policy approval,
or production deployment as completed.

## Environment and rollout flags

- `SAFETY_POLICY_REQUIRED_VERSION` defaults to `1.0`.
- `SAFETY_POLICY_ENFORCE` defaults to `false`.
- `SAFETY_POLICY_DOCUMENT_URL` and
  `SAFETY_POLICY_DOCUMENT_SHA256` must be approved and supplied together.
- `EXPOSE_PASSWORD_RESET_TOKEN` is test-only and is rejected at startup in
  staging and production.
- `BUILD_GIT_SHA` and `BUILD_TIMESTAMP` are non-secret release inputs. Their
  absence produces `available: false` from `/health/build`.

No flag was changed in Azure by this integration work.
