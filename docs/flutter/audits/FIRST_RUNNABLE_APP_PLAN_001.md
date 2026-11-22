# DERMAIRE — First Runnable App Plan (`DERMAIRE-FLUTTER-AUDIT-001`)

- **Target Minimum End-to-End Journey:**
  **Login → Patient Profile → Upload Image → Skin History / Routine → Logout**
- **Audited `main` HEAD SHA:** `5264f6730c53b7a74833f90c4aa9ec7252f97909`
- **Audit Date:** 2026-11-22

---

## 1. What Already Exists in Flutter (`main`)

Every screen and controller required for the minimum journey already exists on `main`:

| Journey Step | Existing Flutter Components (`app/lib/`) | Existing API Calls (`app/lib/services/api_service.dart`) |
|---|---|---|
| **1. Login / Register** | `WelcomeScreen`, `LoginScreen`, `RegisterScreen`, `SafetyResponsibilityScreen`, `PatientEntryGate` (`app/lib/onboarding_screens.dart`) | `POST /api/v1/auth/register`, `POST /api/v1/auth/login`, `POST /api/v1/auth/accept-safety`, `GET /api/v1/users/me` |
| **2. Patient Profile** | `SkinProfileScreen` (`app/lib/onboarding_screens.dart:1253`), `ProfileTab` (`app/lib/app_shell.dart:223`), `AccountController` (`app/lib/account/account_controller.dart`) | `GET /api/v1/users/me`, `PATCH /api/v1/users/skin-profile`, `POST /api/v1/users/profile-review` |
| **3. Upload Image** | `CameraScreen` (`app/lib/app_shell.dart:496`), `GuidedCameraScreen` (`app/lib/capture/guided_camera_screen.dart`), `GuidedCaptureController`, `PhotoPreparation` | `POST /api/v1/captures` (multipart `photo`, `source`, `view`, `Idempotency-Key`), `GET /api/v1/captures/{id}` |
| **4. Skin History / Routine** | `CaptureHistoryScreen` (`app/lib/capture/capture_history_screen.dart`), `HomeTab` / `PatientHome` (`app/lib/home/patient_home.dart`), `ProductsFeatureTab` (`app/lib/products/products_ui.dart`), `RoutineEvidenceScreen` (`app/lib/routine/routine_evidence_ui.dart`) | `GET /api/v1/captures?limit=100`, `GET /api/v1/captures/{id}/image`, `GET /api/v1/measurements/{id}`, `GET /api/v1/home`, `GET /api/v1/products`, `GET /api/v1/routine/entries`, `GET /api/v1/routine/adherence` |
| **5. Logout** | `ProfileTab` Sign Out button (`app/lib/app_shell.dart:325`) -> `DermaireApp._sessionEnded` (`app/lib/main.dart:23-39`) | `POST /api/v1/auth/logout` (`204 No Content`) + local memory & legacy `SharedPreferences` wipe |

---

## 2. Required Backend Endpoints (All Verified Present on `main`)

1. `GET /health` — Backend liveness verification (`backend/app/main.py`)
2. `POST /api/v1/auth/register` & `POST /api/v1/auth/login` (`backend/app/api/v1/auth.py:85, 133`)
3. `POST /api/v1/auth/accept-safety` (`backend/app/api/v1/auth.py:340`)
4. `GET /api/v1/users/me`, `PATCH /api/v1/users/skin-profile`, `POST /api/v1/users/profile-review` (`backend/app/api/v1/users.py:12, 19, 67`)
5. `POST /api/v1/captures`, `GET /api/v1/captures`, `GET /api/v1/captures/{capture_id}`, `GET /api/v1/captures/{capture_id}/image` (`backend/app/api/v1/captures.py:31, 101, 112, 120`)
6. `GET /api/v1/measurements/{capture_id}` (`backend/app/api/v1/measurements.py:27`)
7. `GET /api/v1/home` (`backend/app/api/v1/home.py:16`)
8. `GET /api/v1/products`, `GET /api/v1/routine/entries`, `GET /api/v1/routine/adherence` (`backend/app/api/v1/products.py`, `routine.py`)
9. `POST /api/v1/auth/logout` (`backend/app/api/v1/auth.py:320`)

---

## 3. What Is Missing (Exact Blockers Before First Local Run)

1. **Flutter Configurable `API_BASE_URL` (P0 — Required Small Code PR After Audit):**
   - `app/lib/services/api_service.dart:294-298` currently hardcodes `https://dermaire-api.azurewebsites.net/api/v1`.
   - Required change (in a separate authorized PR, not during this audit): support `--dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1` (restricted to non-release builds or HTTPS-only in release builds).
2. **Android Emulator Cleartext HTTP Config (P1 — Only for Android Emulator):**
   - `app/android/app/src/main/AndroidManifest.xml` does not permit cleartext HTTP to `10.0.2.2`. Add a debug-only `network_security_config.xml` permitting `10.0.2.2` and `localhost`, OR run on iOS Simulator (`127.0.0.1:8000`) first.
3. **macOS Xcode License Acceptance (P0 — Local Host Environment):**
   - On Amr's macOS host, run `sudo xcodebuild -license` once so `flutter test` (native `sqlite3`/`sqlcipher` hook) and iOS Simulator builds (`flutter build ios --simulator`) can execute.
4. **Optional Image Thumbnail Persistence (P2 — Backend Storage Config):**
   - Without `AZURE_STORAGE_CONNECTION_STRING`, `POST /api/v1/captures` still succeeds in `ENVIRONMENT=development` (`201 Created`, `storage: "not_persisted"`, inline quality + measurement), while `GET /api/v1/captures/{id}/image` returns `404`. To render uploaded thumbnails in `CaptureHistoryScreen`, configure either a dev Azure Blob Storage connection string or local Azurite with pre-created private container `skin-records`.

---

## 4. Which PRs Are Prerequisites?

- **Minimum to run the 5-step journey locally:** Only the small `API_BASE_URL` configuration PR (on top of `main`) is strictly required for the basic 5-step journey!
- **Strongly recommended prerequisites before active feature development:**
  - **PR #6 + PR #7 + PR #8:** Fixes the active password-reset mismatch with Backend `main` (PR #3) and activates Flutter CI on `main`.
  - **PR #9 + PR #10:** Ensures `Home` accurately displays `observation_status` returned by Backend `main`.
  - **PR #11:** Adds the full `MeasurementHistoryScreen` for step 4 ("Skin History").

---

## 5. Local Environment Setup (Zero-Cloud First Run)

### 5.1 Backend (Local FastAPI + SQLite)
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ENVIRONMENT=development DEBUG=true DATABASE_URL=sqlite:///./dermaire_dev.db \
  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
Verify: `curl -s http://127.0.0.1:8000/health` returns `200 OK`.

> **Warning:** Do **not** use `backend/docker-compose.yml` unmodified for first local run without providing `POSTGRES_PASSWORD`, `DATABASE_URL`, `SECRET_KEY`, and `AZURE_STORAGE_CONNECTION_STRING`, because `docker-compose.yml:31` sets `ENVIRONMENT=production`, which enforces production startup guards (`backend/app/core/config.py:13, 62`).

### 5.2 Flutter (iOS Simulator Recommended First on macOS)
1. Accept Xcode license once: `sudo xcodebuild -license`.
2. Ensure the checkout is outside iCloud / File Provider folders (per `app/README.md:55-56`).
3. Verify local tooling:
   ```bash
   cd app
   flutter pub get
   flutter analyze
   flutter test
   ```
4. Launch against local Backend (once `API_BASE_URL` dart-define PR is merged):
   - **iOS Simulator:** `flutter run -d <simulator-uuid> --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1`
   - **Android Emulator:** `flutter run -d <emulator-id> --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1` (requires debug cleartext config or HTTPS proxy)

---

## 6. Verification Checklist & Safe Evidence Collection

### 6.1 Step-by-Step Verification
1. **Register & Login:** Create a synthetic test account (e.g., `qa.synthetic.01@example.test`, never a real personal email), accept safety terms, verify `201` on `/auth/register`, then sign out and log back in via `POST /api/v1/auth/login` (`200`).
2. **Patient Profile:** Open `SkinProfileScreen`, select `skin_type` and concerns, save (`PATCH /api/v1/users/skin-profile` -> `200`), complete profile review (`POST /api/v1/users/profile-review` -> `200`), reopen `ProfileTab`, confirm server values persist.
3. **Upload Image:** Open `CameraScreen` -> pick a **non-PII synthetic test image** (never a real face/patient photo) -> submit (`POST /api/v1/captures` -> `201`) -> verify quality decision & measurement response render cleanly.
4. **Skin History / Routine:** Open `CaptureHistoryScreen` (`GET /api/v1/captures?limit=100` -> `200`) and `RoutineEvidenceScreen` (`GET /api/v1/routine/entries` -> `200`), verify the newly uploaded capture receipt appears in descending `received_at` order.
5. **Logout:** Tap Sign Out in `ProfileTab` -> verify `POST /api/v1/auth/logout` -> `204`, navigation resets to `WelcomeScreen`, and pressing Back cannot reopen any authenticated screen.

### 6.2 Safe Evidence Collection (Zero Sensitive Data Exposure)
- **Screenshots:** Use only synthetic test accounts (`@example.test`) and non-identifiable test images. Crop or redact status bars/hostnames if needed.
- **Logs:** Capture HTTP method, path, status code, and latency from Uvicorn logs only — **never** log or commit `Authorization: Bearer ...` headers, JWTs, passwords, `.env` files, or SQLite `.db` files.
- **Test Evidence:** Record exact Git commit SHA, `flutter --version`, `flutter analyze` exit code, `flutter test` pass/fail counts, and Backend Uvicorn request status summary in the PR description or QA handoff report.
