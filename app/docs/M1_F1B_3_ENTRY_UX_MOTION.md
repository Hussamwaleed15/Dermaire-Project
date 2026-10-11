# M1-F1b-3 Stage B — approved entry UX and motion

Amr explicitly approved all Stage A screens/motion and requested Flutter
implementation in this chat. Base: clean main at
`7ca495f77addaefc57f0a87dcf2d3a870f86dda3`, matching fresh GitHub main.
Reviewed actual entry/gate/safety/account code, theme/widgets, tests and Stage A
review/tokens. No backend or production work is authorized.

Plan before editing:

1. Implement approved Cream/Ivory/Burgundy and Charcoal/Graphite/Rose semantic
   theme tokens. Preserve independent clinical colors. Keep tester files intact.
2. Add reusable entry scaffold, branded header, responsive scroll/pinned actions,
   meaningful waiting/confirmed/error UI and motion policy. Use existing assets.
3. Apply the seven approved screens to real password/Google/register/consent/
   hydration flows. No timers fabricate successful auth or server receipts.
   Success is displayed only after verified consent and account hydration;
   continuing into the shell rechecks current session readiness.
4. Bind English/Arabic copy and actual RTL through SDK localizations. Preserve
   email/password LTR, visibility/autofill, unknown profile and medical meaning.
5. Honor system disableAnimations/accessibleNavigation in all new routes,
   button/input/loading/success transitions. No clinical clearance implied by
   brand checkmarks. No animation delays an invalid-session reset.
6. Preserve F1b-1/F1b-2 authority, write/readback, failure and session guards.
   Add regression/accessibility/rendered Flutter checks for both themes,
   keyboard/large text/RTL/reduced motion and safe success/retry/logout.
7. Analyze and run the full suite using existing isolated mocks/network denial.
   Recheck shared main, commit only Flutter files/docs, push normally, leave clean.

No Home/navigation/camera/doctor redesign or later milestone. Global palette
and necessary shared color bindings are foundations; feature layouts remain.
No provider settings, new resources, live OAuth/API testing or release/deployment.

Completion evidence will be recorded after testing.

Implemented:

- `dermaire_theme.dart`: approved semantic `EntryTokens` extension, both palettes,
  pressed/on-action roles, legible Arabic fallback families, consistent button
  targets (52 primary, at least 48 secondary), input radius 14, button radius 16.
  Medical status colors remain independent. Shared neutral widgets and three
  existing shell color bindings adapt to the palette without changing layouts.
- `entry/entry_copy.dart`, `entry_motion.dart`, `entry_widgets.dart`: bilingual
  copy and full Arabic safety guidance, scoped 240ms entry transitions, 100ms
  press feedback, 140ms focus feedback, 180ms status reveal and 220ms success
  reveal. System disableAnimations or accessibleNavigation removes custom
  travel/scale/reveal and replaces looping loading with a static status icon.
  Theme switching and session invalidation are immediate.
- `onboarding_screens.dart`: all seven approved entry states use the actual logo
  and real existing callbacks. Form fields remain native with validation,
  visibility, autofill and LTR email. Safety terms remain scroll-gated. Auth
  failures display safe error/retry UI instead of raw exception contents;
  retry restores the retained form without silently repeating credentials.
- `main.dart`, `dermaire_state.dart`, `pubspec.yaml`, `pubspec.lock`: actual SDK
  English/Arabic localization and welcome language switch. Language is in-memory
  presentation state only. Added SDK flutter_localizations/intl; the lockfile
  matches installed Flutter 3.44.8/Dart 3.12.2 SDK-pinned test dependencies.

Authority before/after:

F1b-1/F1b-2 already blocked the shell until server consent/profile readback.
Stage B preserves those checks and adds an explicit visual success/Continue
step. A token, local preference, acknowledged POST alone, optional profile
field, delay or animation never establishes acceptance. Success requires
current-session confirmed consent plus hydrated account. Continue checks those
conditions again; a callback retained after logout/account switch is inert.
Registration still waits for terms before its POST, then verifies GET and
continues to the existing optional profile flow. No new onboarding-completed
or clinical-clearance state. Authentication/API/consent/account controllers,
recovery and profile editor logic were preserved.

Loading/error flows: auth, consent checking/writing/readback and account
hydration use their real asynchronous state. Sign-out escapes pending auth,
Google picker and consent/profile requests immediately. Timeouts/401/403/5xx,
offline, denied/invalid receipts, retry, duplicate taps and late old-session
responses remain covered. 401 clears the session. No sensitive logging added.

Validation completed in an isolated app checkout:

- `flutter analyze`: no issues.
- Full `flutter test`: **334 passed** (263 existing + 71 new).
- New tests: approved normal-text contrast >=4.5; 56 layout combinations
  (7 screens x 2 themes x 2 languages x 100/200% text), primary/secondary target
  sizes, keyboard reachability, actual Arabic SDK RTL, reduced motion/loading,
  retained success callback after logout/switch, and 10 Google/password error
  and retry cases (401/403/503/offline/timeout).
- Existing consent/profile unit/widget regressions still test strict receipt
  authority, write/readback, real 20s timeout reconciliation, old accepted
  accounts, stale response/session protection and registration. Tests were
  updated to tap the new guarded Continue and to check absent duplicate-write
  controls while loading. No authority assertions were removed.
- Test binding denies unmocked HTTP; all explicit clients use synthetic contracts
  on `flutter-tests.invalid`. No real Google OAuth or production/staging call.
- 28 actual Flutter PNG renders exported for review (all seven states in both
  themes: English 100%, Arabic 200%). Render-only font loading uses bundled
  Karla/Fraunces/icons and Mac Geeza as an explicit Arabic fallback. Native
  app uses platform Arabic fallbacks. Images carry synthetic test states.
- Long content and 200% text scroll rather than shrinking or clipping; the
  footer joins scrolling at large text or keyboard-reduced height. Whole safety
  terms remain reachable before acceptance. Reviewed real rendered logo,
  controls, English and Arabic text. No device/release build or deployment.

Backend needs are separately listed in `M1_F1B_3_HUSSAM_HANDOFF.md`; no required
backend subpart is blocked. This completes only approved M1-F1b-3 Stage B,
not all of M1. Next increment requires a separately scoped request.

Changed Flutter files (19):

- `app/lib/app_shell.dart`
- `app/lib/dermaire_state.dart`
- `app/lib/dermaire_theme.dart`
- `app/lib/dermaire_widgets.dart`
- `app/lib/main.dart`
- `app/lib/onboarding_screens.dart`
- `app/lib/entry/entry_copy.dart`
- `app/lib/entry/entry_motion.dart`
- `app/lib/entry/entry_widgets.dart`
- `app/pubspec.yaml`
- `app/pubspec.lock`
- `app/docs/M1_F1B_3_ENTRY_UX_MOTION.md`
- `app/docs/M1_F1B_3_HUSSAM_HANDOFF.md`
- `app/test/account_hydration_test.dart`
- `app/test/entry_ux_test.dart`
- `app/test/photo_disclosure_test.dart`
- `app/test/product_authority_test.dart`
- `app/test/safety_consent_test.dart`
- `app/test/widget_test.dart`
