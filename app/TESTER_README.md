# Dermaire production tester

This is an isolated functional test harness, not the final Flutter product UI.
Entry point: `lib/main_tester.dart`. Normal `lib/main.dart` is unchanged.

## Download the tester APK

Release: [tester-production-v1](https://github.com/Hussamwaleed15/Dermaire-Project/releases/tag/tester-production-v1).

Download [dermaire-tester-production-debug.apk](https://github.com/Hussamwaleed15/Dermaire-Project/releases/download/tester-production-v1/dermaire-tester-production-debug.apk) from the release assets and install it on an Android device.

This is the **TESTER • PRODUCTION** harness, not the final app. Use disposable Google accounts and non-sensitive images only; authenticated writes reach production. Installation may replace an existing debug Dermaire app. Live Google sign-in and authenticated production flows still require real-device verification.

The APK is distributed as a GitHub Release asset and remains excluded from Git history.

## Launch / install

From `app/`:

```text
flutter run -t lib/main_tester.dart
flutter build apk --debug -t lib/main_tester.dart
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Default environment: https://dermaire-api.azurewebsites.net/api/v1.
The dashboard always displays TESTER • PRODUCTION and the endpoint.
An alternate backend can be supplied using `--dart-define=TESTER_API_BASE_URL=https://your-host/api/v1`; the banner becomes CUSTOM ENVIRONMENT.
No backend provider flags are changed.

## Test order

1. Sign in with a disposable/test Google account.
2. Fetch profile, edit skin type / goal, save, fetch again.
3. Create a routine (also creates a tester-owned product); view it.
4. Record a self-reported check-in; refresh Home / History.
5. Select a non-sensitive JPEG/PNG up to 8 MiB. The real `/captures` quality gate decides acceptance/rejection. Rejected uploads count as a successful exercise of the gate; acceptance is separately shown. Refresh history to confirm server persistence.
6. Ask contextual assistance via `/assistance`. Disabled/unconfigured/degraded providers are marked SKIPPED; no provider settings are changed.
7. Copy the local-only summary if useful. Logout and log back in to verify persistence.
8. Optionally delete the disposable account last. Confirm the permanent deletion warning. The client uses `DELETE /users/me`, clears the session after success, and never manually cleans storage.

Only use disposable accounts and non-sensitive images. All writes reach production and belong to the signed-in account. Do not use this to test someone else's account.

## Audit / reused pieces

Existing GoogleAuthHelper provides native Google ID tokens; ApiService exchanges them at `/auth/google`. Existing session handling is memory-only, purges legacy plaintext credentials, expires on a timer, and clears on 401. Existing profile, product/routine, structured check-in, Home/history, capture upload/controller/picker and account deletion services are reused. Existing product screens are deliberately outside this shell. A typed/validated contextual assistance method was added because the older chat endpoint is a different contract.

## Limitations / Google prerequisite

Android is the intended target. Google OAuth cannot be validated without an Android device and a real tester sign-in. Existing public web OAuth client ID is reused. In Google Cloud Console, the Android OAuth credential must match package `com.example.dermaire_app` and the debug signing certificate SHA-1 from `android/gradlew signingReport`. If the native picker returns configuration error, register that pair in the existing OAuth project; if consent is limited to test users, add the disposable Google account there. No client secret belongs in the app.

Sessions do not survive process restart. No refresh-token flow is available. Logout clears the local session even offline. On expiration sign in again. The summary is local, contains only flow results, resets for a new successful Google login, and includes no tokens, IDs or raw payloads.

Profile editing covers basic skin type / goal only. Image selection reuses the existing picker; no new camera feature. Home is fetched with check-in/capture timeline rows; full product presentation remains separate. Writes are not automatically retried: on an unconfirmed result refresh history before retrying. Creating routines repeatedly creates additional tester products; deletion of the disposable account is the cleanup path.

## Verification

See the task report for analyze/test/build results. A successful APK build does not prove live Google OAuth or authenticated production flows. A teammate must run the sequence above on Android before claiming end-to-end production PASS.

Verified locally: Flutter analyze passed with no issues; full suite passed (150 tests), plus four contextual assistance contract/error tests passed. The six tester-specific tests passed again after the final session-clearing change. Android debug APK build passed using `lib/main_tester.dart`.
Stable APK path (ignored binary): `app/tester-builds/dermaire-tester-production-debug.apk`.
This shares the existing Android application ID and debug certificate, so installation may replace an existing debug Dermaire app. The dashboard banner identifies tester mode. Native Google and all authenticated production operations remain pending real-device verification.
