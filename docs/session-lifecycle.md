# Session lifecycle: Imagine Cup MVP

## Inspected baseline (40e99c0)

- `backend/app/core/security.py`: HS256 access JWT, configured secret and algorithm,
  `sub` (user UUID), `role`, `type=access`, `iat`, `exp`; default lifetime 24 hours.
  Auth register/password login/Google login return access_token, bearer, expires_in,
  user_id, role and full_name. The refresh helper/config exist but no endpoint issues
  or consumes refresh tokens. Doctor QR tokens are separate, time-limited grants.
- `backend/app/api/deps.py`: verifies signature/expiry/type and loads the user on
  every authenticated request. Authorization uses the current database role.
  Deleted users receive 401; the deletion endpoint allows an authenticated retry
  after deletion. Missing exp was previously accepted. Password reset changed the
  password hash but left issued access tokens usable until their expiry.
- `app/lib/services/api_service.dart`: init restored JWT and the entire auth
  response (including another copy of access_token) from SharedPreferences.
  Authentication meant only a non-null token. Logout removed just those two keys.
  Request methods independently interpreted responses, including multipart upload;
  401 could return empty/null data or an error without changing authentication.
- `app/lib/main.dart` and `dermaire_state.dart`: startup opened WelcomeScreen,
  restored local safety/product data and fetched profile/checkins/experiment using
  the restored token. Expired/invalid tokens could leave stale session/local state.
- `onboarding_screens.dart`: password/register/Google entry points persisted auth;
  navigation moved into patient onboarding/AppShell. `doctor_portal.dart` used the
  same auth service, checked doctor role, loaded real authorized patients and had
  logout paths. Patient ProfileTab had account deletion but no sign-out action.
- Deletion cleared product/safety preferences and in-memory account state after
  204; failed deletion preserved session. A 401 did not previously clear it.
  `products/product_repository.dart` has a legacy local preferences repository;
  the production default is RemoteProductRepository. Journal, goals, profile,
  rewards and product-controller data live in DermaireState; page-specific chat
  and doctor workspace data are discarded when their routes are removed.

## Implemented model

Access-token-only, same configured 24-hour default; no refresh flow or database
migration. Re-authentication is required on expiry, invalidation and every app
restart. This deliberate MVP usability tradeoff removes persistent bearer-token
storage without introducing a platform storage dependency or refresh protocol.
No token or auth response is written to SharedPreferences; init always discards
legacy token/user/product/safety keys, including malformed restored data. Theme
preferences remain. Memory contains credentials only while the session is live.
OS snapshots, process-memory inspection and old device backups remain outside
this guarantee; persistent sessions would require vetted secure storage later.

New access tokens include unique random jti and a server-keyed HMAC credential
stamp of the stored password hash (never the password/hash itself). Authentication
requires exp/iat/sub/jti/credential, checks signature/expiry/type, current password
stamp and session revocation. Password reset therefore invalidates all previous
sessions; successful Flutter password reset also clears its local session immediately.
New password login works normally. Roles continue to come from the DB,
not trusted client/JWT role values. Refresh and doctor QR tokens cannot authorize
normal authenticated requests.

POST /api/v1/auth/logout (Bearer, 204) revokes only that token via an existing
AuditLog SESSION_REVOKED record, keyed by actor and jti. Do not remove these records
while the corresponding token can still be valid. This uses the existing actor
index; a dedicated indexed session store is a later scaling option, not needed
for the MVP. No token/credential is stored in audit details. Other devices remain
signed in, unless their password is reset or account deleted. Account deletion
continues to reject the deleted identity on normal routes and allows idempotent
DELETE retry, while invalid/expired/revoked/password-invalidated tokens receive 401.

Flutter uses a single response handler for all API methods and multipart uploads.
401 on a request carrying the current token clears session immediately, removes
sensitive account preferences, clears DermaireState and removes private routes.
An expiry timer does the same while idle; a clock check prevents requests with a
locally expired token, including after suspension. Late responses from an older
session are rejected before they can restore private data; 403/server/network
failures do not invalidate otherwise valid sessions. Public auth endpoints do not
send the existing bearer token, so a failed sign-in is not treated as session expiry.

Logout clears local state before attempting server revocation (10-second timeout).
Offline/failed logout cannot guarantee server revocation: a copied token remains
usable until its fixed expiry or password reset/account deletion. It is never
restored locally. There is no offline authenticated restore or automatic refresh.
Google's native account picker may remember its provider account; this is separate
from Dermaire authorization and every Google sign-in must obtain a new backend JWT.

## Compatibility and deployment

Auth response fields and role semantics are unchanged. Logout is additive; no new
settings or schema migration. Previously issued tokens lack the required stamp/jti
and receive 401 after backend deployment; users must sign in once again. Deploy
backend with the updated Flutter client to get server logout plus local cleanup.
Older clients cannot provide the new consistent 401 UI behavior. Do not claim that
an offline local logout revokes a token on the server. Keep the production secret
configuration milestone intact; do not change secrets as part of this work.

## Verification

Focused backend cases cover valid access, expiry, invalid signature/format, missing
expiry/legacy claims, logout rejection (including deletion), another session staying
valid, password reset invalidation and subsequent successful login. Existing
account deletion and doctor/patient role tests remain in the suite.
Flutter cases cover memory-only valid login, legacy stale/malformed restore,
401 for profile/products/multipart, clearing health state, idle-expiry navigation,
logout server request, offline logout and rejection of late profile responses.
Existing auth/UI/deletion/doctor tests are updated for the memory-only model.

Final local verification: backend pytest 84 passed; Flutter tests 64 passed.
Flutter analyze: no issues. git diff --check: passed. Existing UTF-8/non-ASCII
characters verified unchanged. No secrets or unrelated files included.
