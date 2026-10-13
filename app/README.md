# Dermaire

Dermaire is a Flutter prototype for personal skin experiments. It includes onboarding, product and interaction management, experiment and check-in flows, reports, rewards, a safety-limited app guide, and a clinician workspace demonstration.

## Current Flutter product and workflow

Dermaire is English-only, including on devices configured in Arabic. Language
selection/localization and custom RTL support are not product requirements.
Implement directly in Flutter using the approved design, in small testable
increments. Separate visual prototypes, HTML mockups and Stage A approvals
are no longer required; expensive visual generation needs an explicit request.

See [permanent Flutter rules](AGENTS.md) and the
[English-only cleanup decision](docs/M1_F1B_3C_ENGLISH_ONLY.md). Historical audits
and earlier milestone reports record their original context; these current rules
supersede their language and visual-approval requirements.

## Status

This repository is **not production medical software**. Authentication, camera analysis, OCR, messaging, notifications, clinical storage, consent enforcement, and server-side authorization require real services before human use. Demo screens and records are labelled in the UI.

## Architecture

- `lib/products/`: typed product domain, validation, repository, controller, and UI.
- `lib/access_control.dart`: role and permission policy used by the clinician demo.
- `lib/doctor_portal.dart`: clinician sign-in demo, authorized patient list, patient details, append-only notes, and local audit events.
- `lib/chatbot.dart`: deterministic help responses and urgent red-flag escalation.
- `lib/dermaire_state.dart`: shared prototype state and local preferences.
- `lib/app_shell.dart`: patient navigation and remaining prototype flows.

Product data and first-run preferences persist locally with `SharedPreferences`. Other health and experiment data is still prototype state.

## Verification

```sh
flutter analyze
flutter test
flutter build web
```

See `docs/READINESS_AUDIT.md` for the current readiness score, evidence, known limitations, and required production work.

## iOS simulator development

The current native dependency set requires **iOS 14 or later** because
`file_picker_darwin` 2.0.0 requires 14.0. Runner's Debug/Release/Profile settings
and regenerated Flutter SwiftPM package use that deployment floor. Native
plugins use SwiftPM; all four application-owned Xcode project/workspace
`Package.resolved` files are tracked. Generated packages/build caches are ignored.

From `app/`, run `flutter pub get`, then
`flutter build ios --simulator --debug --target lib/main.dart`. Use
`flutter devices` to select an installed iPhone simulator and
`flutter run -d <simulator-UUID> --debug --target lib/main.dart` to install/launch.
Use a local checkout outside File Provider-managed folders to avoid observed
Finder-metadata signing contamination. See the verified environment, lockfile
inventory and startup evidence in [iOS launch repair](docs/IOS_SIMULATOR_LAUNCH_REPAIR.md).
