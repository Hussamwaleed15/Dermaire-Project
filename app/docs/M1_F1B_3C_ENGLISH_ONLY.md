# M1-F1b-3c — English-only product alignment

## Official decision (2026-10-12)

Amr confirmed that Dermaire is English-only. This supersedes all previous
Arabic/bilingual/RTL requirements, Arabic fonts, language switchers and parity
expectations. All application-owned UI copy is English across authentication,
onboarding, Home, profile, camera, guide, reports, routines, experiments,
notifications and clinician screens. Adding multilingual features requires a
new explicit decision from Amr.

Future Flutter work uses direct implementation: inspect actual source/current
Git state, concise internal plan, implement the approved design in small
increments, test/analyze/fix, commit/push verified changes, concise report.
Separate visual simulations, HTML prototypes and Stage A/Stage B approval
workflows are discontinued. Real Flutter screenshots after implementation are
optional verification; expensive visual generation requires an explicit request.
The durable rules are in `app/AGENTS.md` and linked from `app/README.md`.

## Source and scope

Started from clean shared main at
`d4d1e8dc5d892b0482ad0faa86a1cb532dc3e8f7`, confirmed equal to origin/main and
fresh GitHub main before editing. Flutter-only cleanup, no UI redesign or auth
rewrite. Historical architecture/product/agent audit reports were not rewritten.
The previous entry implementation report now points to this superseding decision.

## Removed features and preserved behavior

- Removed the welcome language button with its tooltip/callback; no empty
  placeholder remains. Theme control and the approved header/layout remain.
- Removed mutable language state/toggle, contextual locale lookup, Arabic copy
  and error/safety translation maps. The exact existing English expressions
  remain; shared English entry copy is independent of context/locale/preferences.
- Fixed MaterialApp locale/supportedLocales to English only. Built-in English
  Flutter delegates supply English framework labels on Arabic devices. No
  forced whole-tree Directionality or keyboard-language override was added.
- Removed explicit Arabic font fallbacks and unused flutter_localizations/intl
  dependencies. Karla, Fraunces and the original Dermaire logo are unchanged.
  No Arabic font assets had been bundled, so no needed asset was deleted.
- Removed discontinued Arabic parity/font-export/language-switch expectations;
  retained both-theme/large-text/keyboard/reduced-motion layout checks. Removed
  the obsolete RTL wrapper in the photo-disclosure test.
- Reviewed the wider Flutter source. Remaining Arabic strings in chatbot.dart
  are pre-existing input red-flag/help keyword matching, not UI translations or
  language selection. They return English replies and are retained to avoid
  weakening existing medical escalation for free-form user input. No new
  multilingual feature was added. Other application-owned UI is already English.

Approved palette, typography, component geometry, semantic medical colors,
loading, 240ms entry routes, press/focus/status/success motion, reduced motion,
accessibility and responsive scroll behavior are preserved. entry_motion.dart,
API/Google/auth services, consent/account controllers, profile editor and
registration sequence are unchanged. F1a disclosure remains exact English.

## Obsolete preference handling

F1b-3 language selection was in memory only, not persisted. No real language
preference schema exists to migrate. Removing state/lookup and forcing effective
English safely ignores any obsolete language-like key without clearing it or
unrelated preferences. Tests seed plausible legacy keys solely as negative
fixtures, not as an invented product schema. Dark-mode persistence remains.
No account, consent or profile storage behavior was changed.

## Regression validation

Verified in the actual current Flutter checkout:

- `flutter analyze`: no issues.
- Full `flutter test`: **321 passed** (305 retained/updated + 16 new).
- Previous suite had 334 tests. Removed 28 discontinued Arabic parity cases
  and the one language-switch test, while retaining their English layout/motion
  equivalents. No auth/authority/session regression was removed.
- Targeted English/entry/disclosure suites: 68 passed.
- Existing test binding/invalid-host mocks are unchanged and deny unmocked
  HTTP. No real production/staging API, account, Google OAuth or release build.
- Diff review confirms no changes in API/Google services, consent/account
  controllers, motion implementation, profile editor/recovery logic, shared
  feature screens, medical input escalation, tester or HTTP isolation setup.
- No new visual prototype, HTML simulation, gallery or screenshot export was
  generated for this cleanup.

New tests cover
all seven entry states in both themes on Arabic device locale, English framework
labels, absent language controls, fixed locale after device locale changes,
ignored legacy preference fixtures and retained unrelated/dark preferences.
Existing auth/Google/password/registration, server consent GET/write/readback,
profile hydration/readback, session/account isolation and transport-denial
regressions remain. No live production/staging API or real Google OAuth.

## Limitations and Hussam boundary

This fixes application-owned UI; free-form names, notes and user messages are
not translated, restricted or silently rewritten. Generated AI/report/API content
remains backend-owned. For Hussam: future AI responses/reports/notifications
should use an English output contract for the English-only product; confirm it
with isolated response fixtures if needed. Flutter does not translate or
fabricate server clinical content. No backend issue blocks this cleanup.

Existing backend follow-ups for policy currency/profile review semantics remain
in earlier Hussam handoffs. No backend/Azure/database/AI/provider/production or
Production Tester Client changes, builds or deployments were performed. This
increment ends at M1-F1b-3c; M1-F2 does not start automatically.

## Modified files (15)

- `app/AGENTS.md`
- `app/README.md`
- `app/docs/M1_F1B_3C_ENGLISH_ONLY.md`
- `app/docs/M1_F1B_3_ENTRY_UX_MOTION.md`
- `app/lib/dermaire_state.dart`
- `app/lib/dermaire_theme.dart`
- `app/lib/entry/entry_copy.dart`
- `app/lib/entry/entry_widgets.dart`
- `app/lib/main.dart`
- `app/lib/onboarding_screens.dart`
- `app/pubspec.yaml`
- `app/pubspec.lock`
- `app/test/english_only_test.dart`
- `app/test/entry_ux_test.dart`
- `app/test/photo_disclosure_test.dart`
