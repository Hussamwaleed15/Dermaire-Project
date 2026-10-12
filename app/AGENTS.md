# Dermaire Flutter — permanent product and workflow rules

Amr confirmed these rules on 2026-10-12. They supersede earlier Arabic/bilingual/
RTL requirements and separate visual Stage A/Stage B approval workflows in
historical audits or milestone reports. See `docs/M1_F1B_3C_ENGLISH_ONLY.md`.

- Dermaire application-owned UI is English-only, including patient entry,
  profile, Home, camera, reports, routines, experiments, notifications, guide
  and clinician UI. Do not add localization, language preferences/switchers,
  Arabic fonts or RTL-specific features unless Amr explicitly changes this.
  Preserve normal system keyboard, accessibility and user-provided content.
- Inspect current source and shared Git state, make a concise internal plan,
  implement directly in Flutter using the approved design system, test and fix,
  then commit and push verified small increments. No separate visual approval
  stage, HTML simulation/mockup or extensive preimplementation gallery. Only
  generate expensive visuals when explicitly requested. Real Flutter screenshots
  after implementation are optional verification, not a prerequisite.
- Preserve Cream/Ivory/Burgundy light and Charcoal/Graphite/Rose dark semantics,
  typography, responsive layout, reduced motion, accessibility and purposeful
  entry motion. Keep medical safety colors distinct from brand colors.
- Preserve server-authoritative consent and profile readback, session/account
  isolation and truthful photo disclosure. Never fabricate policy version,
  onboarding completion, clinical clearance or local-only acceptance.
- Amr owns Flutter. Hussam owns backend, Azure, database, AI and API contracts.
  Flutter tasks must not change those systems, provider/production settings or
  the separate Production Tester Client. Document contract needs for Hussam.
- Use isolated mocks/fake transports and keep test HTTP denial. No production
  accounts, real Google OAuth/API tests or production build/deployment. Run
  `flutter analyze` and the full `flutter test` suite; fix failures before delivery.
- Respect concurrent work; stage only intended Flutter/docs files, push normally
  to origin/main when authorized and verified, never force-push. Leave clean.
  Stop at the requested increment; do not automatically start M1-F2.
