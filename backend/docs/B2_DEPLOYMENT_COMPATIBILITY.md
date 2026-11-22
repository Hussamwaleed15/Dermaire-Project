# B2 deployment compatibility and provenance

Date: 2026-11-12 (Africa/Cairo).

This document covers code and release evidence only. It does not authorize or
perform an Azure change, database query, migration, staging deployment or
production deployment.

## Build provenance contract

Release packaging supplies these public, non-secret settings:

- `BUILD_GIT_SHA`: the complete 40-character Git commit SHA packaged for release.
- `BUILD_TIMESTAMP`: an RFC 3339 timestamp with an explicit timezone.
- `VERSION`: the API version, currently `1.0.0`.

`GET /health/build` returns the validated values, the API version and the
required Alembic revision with `Cache-Control: no-store`. Missing or malformed
inputs produce `available: false` and null provenance fields. The raw invalid
values are never returned. Build provenance contains no repository credential,
Azure identifier, database location or connection detail.

The endpoint identifies the package only. It does not prove that a deployment
completed, that traffic reached every instance or that a database migration ran.

## Compatibility matrix

| Application package | Required database revision | Expected readiness | Release action |
|---|---|---|---|
| Historical live package (58 OpenAPI paths / 68 schemas; exact SHA unknown) | Not proven by the B2 read-only audit | Current live probe is insufficient to prove F8 compatibility | Do not infer compatibility; inventory through an approved read-only channel |
| `origin/main` at `b995873f2b76e0c37a08f23fbf40322174aba6fe` | `20261024_14` | Ready only when the managed database reports exactly the required revision and storage/journal checks pass | Qualify in isolated staging before any production proposal |
| Future package | Revision declared by `REQUIRED_ALEMBIC_REVISION` in that package | Same exact-revision rule | Update this matrix and migration evidence in the release PR |

Readiness intentionally returns only `database: available|unavailable`. It does
not disclose the observed revision, database host, database name, SQL text or
driver error. The public build endpoint exposes the required revision because it
is package compatibility metadata, not a live database observation.

## Proposed staged upgrade plan (not executed)

1. Use a separately approved read-only administrative channel to record the live
   Alembic revision and schema drift result without exporting application rows.
2. Produce a release artifact from the reviewed commit and inject its SHA and UTC
   build timestamp. Retain the artifact digest and dependency manifest.
3. Restore or create an isolated staging target and rehearse every required
   migration there. Verify row invariants, `alembic check`, rollback constraints,
   readiness, OpenAPI 115/117 and focused PostgreSQL concurrency tests.
4. Deploy the artifact to staging only after separate approval. Confirm
   `/health/build` matches the reviewed commit and all instances converge.
5. Document migration duration, locks, failure recovery, backup/PITR evidence and
   an application rollback package compatible with the post-migration schema.
6. Submit a separate production migration/deployment proposal. Do not migrate or
   deploy production from this B2 code-only pull request.

## Security headers

All HTTP responses receive `X-Content-Type-Options: nosniff`,
`X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: no-referrer` and a restrictive
camera/microphone/geolocation `Permissions-Policy`. Staging and production also
receive one-year HSTS. `includeSubDomains` is intentionally withheld until an
authoritative DNS and TLS inventory proves that every subordinate host is HTTPS
only; enabling it without that evidence could make an unrelated subdomain
unreachable. Existing application-provided values are preserved. A Content
Security Policy is not added globally because Swagger, ReDoc and the bundled
static pages need a route-specific inventory first; an untested global policy
could silently break those interfaces.

## Continuous verification

The Backend CI workflow runs on the exact pull-request commit. It installs from
the checked-in requirements, starts an isolated PostgreSQL service bound to the
test-only gate port, enables all disposable PostgreSQL fixtures, runs the full
Backend suite, compiles the application, checks the Git diff for whitespace
errors and records the OpenAPI path/schema counts. It also creates a source
archive directly from the checked-out commit plus a small provenance statement,
dependency manifest and SHA-256 digest, then uploads those files as CI evidence.

That archive is verification evidence, not an approved deployable release. A
release pipeline must build the actual deployable artifact from the reviewed
commit, inject `BUILD_GIT_SHA` from that immutable checkout (never free-form
operator input), retain the deployable artifact digest and verify
`/health/build` against it before promotion.
