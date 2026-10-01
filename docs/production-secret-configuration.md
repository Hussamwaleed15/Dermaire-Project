# Production secret configuration

Set `ENVIRONMENT=production` and supply `SECRET_KEY` through deployment environment settings. Generate a unique, cryptographically random secret (for example, 32 random bytes encoded as 64 hex characters). Never commit or log its value. Existing environment-variable names are unchanged.

`app.core.config.Settings` reads process environment variables before UTF-8 `.env` values. The shared settings instance is constructed during application import, before database initialization and API startup. Production and staging reject a missing key, an empty/whitespace-only key, or the built-in development key (including surrounding whitespace), with a clear configuration error that omits input values. Docker Compose requires `SECRET_KEY` from its environment or Compose `.env` and passes it to the API; application validation still rejects the development key.

Local development defaults to `ENVIRONMENT=development` and may use the built-in development key. Tests can explicitly select `ENVIRONMENT=test`. Supported environments are `development`, `test`, `staging`, and `production`; `dev`, `testing`, and `prod` are aliases. Values are case-insensitive with surrounding whitespace ignored; unknown values fail validation. Deployments must explicitly select production; omitting `ENVIRONMENT` preserves the existing local development behavior.

Access, refresh, and doctor QR tokens, token verification, and account-deletion pseudonyms all use `SECRET_KEY`; there is no alternate signing-secret fallback. Password reset codes use secure random generation, and token exposure defaults to disabled. Google client IDs are public audience identifiers, not signing secrets. Azure credentials and database settings are outside this milestone.
