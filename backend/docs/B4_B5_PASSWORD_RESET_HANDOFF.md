# B4/B5 password reset security handoff

Date: 2026-11-13 (Africa/Cairo).

## API compatibility

The existing endpoints and successful response shapes remain unchanged:

- `POST /api/v1/auth/forgot-password` always returns the same generic body.
- `POST /api/v1/auth/reset-password` still accepts email, eight-digit code, and
  new password, and returns the updated user on success.

Invalid email, non-eight-digit codes, and passwords shorter than eight or longer
than 128 characters now fail schema validation. Flutter must continue treating
the forgot-password response as non-confirmation that an account exists.

## Security properties

- `EXPOSE_PASSWORD_RESET_TOKEN=true` is rejected at application startup in
  staging and production.
- New codes are stored as HMAC-SHA-256 values keyed by the application secret.
  A bounded compatibility check accepts legacy SHA-256 codes only until their
  existing 30-minute expiry.
- PostgreSQL row locking makes successful code use single-use across replicas.
- Five wrong guesses invalidate the code; expiry and repeat-request replacement
  remain enforced.
- The database-backed per-email rate window is shared across application
  replicas. It stores only a keyed pseudonymous subject, never the raw email.
- Provider delivery runs after the generic response and provider exceptions are
  contained without returning or logging the code, recipient, credentials, or
  provider details.
- Changing the password changes the credential stamp, invalidating previously
  issued access tokens.

## Operations and open dependencies

Defaults are three reset requests per 15 minutes per normalized email. Tune only
through reviewed configuration and provider telemetry. This control protects a
single identifier; Azure Communication Services quotas and edge-level abuse
controls remain required for distributed attacks spanning many identifiers.

No real email is sent by tests. CI uses monkeypatched delivery and a disposable
PostgreSQL 18 database. This change performs no deployment, live database
operation, Azure configuration change, or Flutter edit.
