# DERMAIRE Patient Architecture, Design & Execution Roadmap

10 October 2026, Africa/Cairo. Anchored in inspected source `17f6552b55eee2e8ab87c9019ab1a0a87384662b`. Proposal only; no code, design file, deployment or provider configuration changed.

## Existing architecture to retain and evolve

Flutter uses Material 3, ChangeNotifier, repository boundaries and plain Navigator/MaterialPageRoute. Product has a typed model; many other resources are untyped maps. Controllers contain useful generation guards, provenance validation, readback and explicit unknown/unconfirmed states. `ApiService` is a shared singleton; `DermaireState` aggregates controllers and account state; six-page IndexedStack builds the app shell; onboarding and app_shell are large combined files. Separate main_tester.dart has a production-bound harness.

Keep this technology foundation initially. Introduce typed DTOs/adapters for SafetyEvaluation, PersonalSkinModel v2, ReviewStatus, Capture/Measurement and richer assistance, aligned to Pydantic schemas. Keep repository injection and generation/session guards. Move feature pages out of app_shell/onboarding only as each vertical flow is implemented; do not rewrite all state management or introduce a new router without a concrete lifecycle/deep-link need. Inject immutable environment/API configuration at composition root, separating official/tester and production/nonproduction identities.

Use a shared async resource state with loading, empty, fresh, stale, partial, permissionDenied, unavailable, and writeUnconfirmed. Stale data may support cached viewing, never a claim of current medical clearance. A write acknowledgement followed by failed refresh must not become either fake failure or fake current readback: display “saved; latest view unavailable” when contract supports it and avoid duplicate retry. UI event routing is separate from medical state. Safety and clinical decisions are always server projections.

## Semantic token strategy

Existing DermaireColors uses tan/caramel (#8B5E3C primary), with scattered fixed light colors. Approved burgundy palette is not implemented. Preserve existing light/dark ThemeData scaffolding, Karla/Fraunces assets and reusable cards as migration points.

Three layers: **primitive values → semantic roles per mode → component tokens**. Centralize spacing, radii, typography, elevation, motion and clinical states. `ColorScheme` covers standard Material roles; `ThemeExtension` can carry clinical and expressive component roles. Screens access roles, not brand hex values. Clinical state colors are independent from brand success/selection and always paired with text/icon. Gradients use low-amplitude surface/rose tones; never encode urgency as a decorative gradient.

| Semantic role | Light proposal | Dark proposal / rule |
|---|---|---|
| Brand primary / onPrimary | #681B22 / #FFFFFF | Light rose primary with deep onPrimary; validate after choosing rose value |
| Brand deep / emphasis | #481116 | Warm ivory emphasis on dark surface |
| Canvas | #FAF4EC | Deep warm burgundy-neutral; proposed #1B1214, validate in component QA |
| Surface / raised surface | #FFFCF8 / ivory variant | Proposed #281B1E / #332327; avoid simply dimming light tokens |
| Text primary / secondary | #481116 / distinct dark neutral role | #FAF4EC / lighter warm neutral role; no reused light ink |
| Rose/blush accent / selection | Named accent and muted container roles, final shade via prototype | Corresponding dark container + readable text; not medical safety |
| Clinical track / unknown | Neutral label with unknown icon/text, separate info container | Explicit unknown persists in dark mode |
| Clinical low_risk_self_care | Distinct clinical color + readable onContainer | Wording preserves evidence limits; never label “safe” just from missing flags |
| Clinical doctor_review | Amber or distinct caution roles; final pair tested | Text/icon plus canonical instruction and age |
| Clinical urgent | Independent red/urgent foreground-container pair | Persistent urgent state, no celebratory morph, no dismissal implying resolution |
| Border / focus / disabled | Separate visible border/focus roles | Focus checked across each surface; disabled status never substitutes for permission explanation |

Measured opaque sRGB pair contrast (computed locally, relative luminance ratio, rounded):

| Pair | Ratio | Implication |
|---|---:|---|
| #681B22 on #FAF4EC | 10.87:1 | Suitable candidate for normal text |
| #481116 on #FFFCF8 | 15.02:1 | Suitable candidate for primary text |
| White on #681B22 | 11.87:1 | Suitable button pair |
| White on existing #8B5E3C | 5.58:1 | Existing solid button pair passes normal-text target |
| Existing #6E8F6C on #EAF0E6 | 3.12:1 | Not suitable for normal small text |
| Existing #C69A45 on #F5EBD6 | 2.19:1 | Not suitable for normal small text/icons |
| Existing #B0503A on #F6E3DD | 4.18:1 | Below normal-text target |

These are token-pair checks, not a full accessibility certification or proof every pair is used for text. Validate actual foreground/background, alpha compositing, gradients, focus rings, disabled states and dark mode. Flutter's official accessibility checklist recommends contrast, screen reader, large text and touch target checks: [Flutter accessibility](https://docs.flutter.dev/ui/accessibility). Define test gates of >=4.5:1 normal text, >=3:1 large text/nontext controls, minimum 48 logical-pixel primary touch targets; keep clinical meaning available without color.

Typography: retain Fraunces for restrained English headings and Karla for readable body if user prototypes accept them. Bundle an appropriate Arabic heading/body font pair after legibility/licensing checks; do not assume Latin assets cover Arabic. Semantic scales rather than per-screen tiny sizes; scalable body, minimum readable secondary labels, clear clinical hierarchy, numeric units and localized dates. Test 200% text scale and narrow devices without clipping. Arabic/English ARB strings and generated localization, delegates/supportedLocales, directional padding/alignment and bidi numbers from the first slice. Official localization mechanism: [Flutter internationalization](https://docs.flutter.dev/ui/internationalization). Canonical backend enums stay stable; clinical guidance needs a versioned localization approach, not uncontrolled machine paraphrasing.

## Reusable patient components

- PatientPage/section scaffold extending DermairePage, responsive list content, coherent heading hierarchy and focus order.
- PriorityActionCard with stable ID, authoritative reason, due/age/eligibility, named destination and state-specific CTA.
- ClinicalStatusPanel for Safety/clinician instructions, freshness/uncertainty, provenance and actionable read-only guidance; pinned above decorative content.
- EvidenceCard with patient_reported/system_observed/deterministic_derived/clinician_authored/ai_inferred label, unit, confidence/age, and expandable source references.
- RoutineSlotCard with configured instruction and reported-use state separate; confirmed completion animation plus undo/correction only if backend contract supports it.
- CaptureGuidanceOverlay/QualityResult/ProcessingState with real server phase and retake; privacy disclosure before upload.
- TimelineItem and ComparisonViewer with secured image loading, explicit noncomparable result, accessible dated list alternative to slider.
- ConsentSheet, PermissionExplanation, UnconfirmedWriteBanner and safe DeleteAccountDialog; no local flag claims backend revocation/deletion.
- AssistantSuggestionCard with grounded facts, unknowns, provider mode and nonexecuting next step; later action approvals use a distinct server broker.

Keep context-dependent shapes: calm rounded evidence cards, tighter clinical notice panels, larger capture/primary-action containers. Identity and continuity come from stable source IDs and semantic geometry, not arbitrary shapes on every screen.

## Shell and navigation options — decision remains open

| Option | Benefit | Cost / validation |
|---|---|---|
| Four destinations Home / Journey / Routine / Profile with centered Camera action | Longitudinal loop visible, camera prominent | Product access needs contextual/library route; test discoverability and Arabic label lengths |
| Home / Journey / Care / Profile with centered Camera action | Care groups routine/products/experiments | Extra layer for daily routine; test task time and comprehension |
| Smaller shell with Home / Journey / Profile and centered Camera action | Less density | Routine may be buried; likely unsuitable if adherence is a dominant daily action without Home shortcut |

Current six tabs plus chat FAB do not select the final model. Camera is an action launching Observe flow, not a mandatory navigation destination. Keep back stacks and draft recovery per flow; clinician shell separate after authenticated backend role. No simulated patient role toggle. Prototype 2 options with synthetic data, measure routine/check-in/history/doctor-guidance task success and screen-reader traversal, then obtain navigation decision later.

## Motion architecture and performance gates

Current AnimatedBuilder updates state; it is not itself expressive animation. Existing routes use MaterialPageRoute and chat scroll uses 200ms. No centralized reduced-motion policy, Hero/card morphs, spring sheets or haptics were found.

Proposed MotionTokens plus MotionPolicy read system disableAnimations/accessibleNavigation and user setting; all custom transitions obey it. Reusable implicit transitions for state/card size/color, explicit controller for multi-element capture continuity, shared-element Hero only between meaningful stable source identities. Sheets use restrained spring settling; urgent state appears promptly and remains readable. No animation delays an emergency instruction or confirms an unacknowledged write. Standard Flutter options are documented in [Flutter animations](https://docs.flutter.dev/ui/animations); no new animation package required for the initial slice.

| Interaction | Default proposal | Reduced motion / authority boundary |
|---|---|---|
| Card→detail | 220–320ms size/shape/shared-content continuity | Immediate or brief fade; destination state from same server entity |
| Context sheet | 240–360ms restrained spring, recover focus on close | Immediate placement/fade; no background scroll/focus trap |
| Routine confirmation | 140–220ms checkmark/state change after server confirmation | Immediate icon + text/live announcement; no streak/medical reward implied |
| Camera permission→preview | Gentle entrance, guidance stable over live preview | Static guidance; permission denial gives upload alternative |
| Capture upload / quality | Indeterminate processing during request; accepted/rejected from response | Text and progress semantics; no fictitious face scan/percent/status steps |
| Capture→result | 200–280ms continuation of preview thumbnail | Immediate result; label proxy metrics and quality limits |
| Timeline comparison | Direct manipulation; settle to dated pair | Accessible buttons/list summary; no autoplay/photo carousel |
| Home reprioritization | Stable layout, bounded local state change | Immediate priority order; retain focused item; urgent updates announced once |

Haptics are optional per user/device, short confirmation or error cue; never sole feedback and never continuous processing buzz. Avoid full-resolution Image.memory retention and repeated decoding; constrain previews and maintain secure bytes lifecycle. Scope rebuilds to feature controllers, profile picture/camera frame never triggers full DermaireState tree. List virtualization for history, bounded image cache, small clipped regions and no expensive full-screen blur/opacity/saveLayer. Follow [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices).

Performance DoD: profile in release/profile mode on agreed representative devices, target p95 UI and raster times within one frame budget (16.7ms at 60Hz, 8.3ms at 120Hz if supported), document measurement/device; no repeated long stalls during preview/upload/result; memory returns near baseline after leaving camera/image history; test lower-end GPU and photo decoding. Targets are proposed gates, not results from this audit. App must remain correct if motion/haptics are disabled.

## Prioritized contextual Home

Use stable greeting and Observe access plus dynamic ordered actions: (1) current urgent Safety, (2) visible clinician review/instruction requiring attention, (3) uncertainty/failed writes requiring refresh, (4) due observation/routine/experiment tracking, (5) learn/compare insights. Safety and clinician state originate server-side. Other ranking rules are proposed presentation policy, to be made explicit and tested. Never hide urgent risk because routine is complete, compute medical urgency on device, or use stale status to clear risk.

Return after absence: refresh authorized sources, show freshness and missed reporting as unknown, ask gently whether circumstances changed when useful; never infer nonadherence, illness or restart treatment. Agent can suggest review/tracking; medical decisions stay backend/clinician. Current `/home` lacks these projections, so first consume `/safety`, `/doctor/review-status` and PSM via safe composition; a combined authoritative feed is a separate backend improvement if consistency/versioning requires it.

## Execution roadmap — vertical flows with exit gates

All milestones below are future work. No deployment is included. Patient milestones M1–M5 complete before expanding doctor UX M6. Patient-visible existing clinician guidance is included in M1/M3 despite clinician UX coming later.

### M1 — Trusted patient entry → Observe → authoritative Home

**First implementation milestone recommendation.** Dependencies: synthetic nonproduction environment binding, current contracts above; resolve B1/B2 below. Scope: lifecycle/consent/privacy correctness and one complete observation path, with semantic light/dark/Arabic-English/reduced-motion foundation restricted to this flow.

Tasks: immutable environment selection and production-denying test setup; hydrate profile/role/safety acceptance from server after password/Google login; wire `/auth/accept-safety`; route incomplete onboarding; correct upload/privacy and sharing placeholder claims; add structured risk screen with unknown/yes/no semantics; record report-only observation; display authoritative completion distinct from metric baseline; read `/safety` and visible clinician status; typed DTOs/repositories, safe stale state and session guards; account delete/logout remains existing contract. Keep navigation final decision open using existing shell/temporary entry action. Do not enable Vision/OpenAI/email or redesign every screen.

**Definition of Done:** UI/API/state: synthetic password/Google adapter fixtures → onboarding consent server readback → observation POST → history/Home readback with matching ID and explicit completion. Unknown/urgent/clinician cases follow canonical guidance; no device override. Loading/empty/error/unconfirmed/401/403/timeout/late-response/account-switch cases visible and tested. Permission: disclosures scoped to signed-in account, image upload only after clear disclosure and optional choice; no testers. Motion: confirmed observation transition plus reduced-motion/large-text/RTL parity. Offline: cached-view policy explicit; observation draft may remain local, no silent medical writes or false completion; reconnect refresh before retry. Tests: existing suites plus meaningful contract regressions for report-only completion/idempotency, Google consent, null clinical states, urgent visibility and privacy language; staging synthetic app→API verification gated by user-approved environment access. Exit: no P0 trust/safety discrepancies in this slice, reproducible synthetic evidence, no production modification.

### M2 — Guided image → quality → measurements → private comparison

Depends on M1, platform camera permission choice and B3/B4 decisions. Tasks: actual camera preview/pose/light guidance or honest upload fallback; explicit image consent, bounded bytes; use capture response proxies and quality reasons; secured owner-only image repository; measurement detail/age/provenance; before/after/timeline comparison with noncomparable states; decide how capture links to observation without conflating score systems. Backend multi-stage jobs only if needed; current synchronous API supports one “checking” phase.

**DoD:** UI/API/state: accepted/rejected/not-stored/failure states use actual responses, returned measurements displayed with units/version/limitations and authenticated photo reads. Loading/errors: failed save/refetch/lost response resolve with server capture identity; rejected image never represented as retained/measured. Permissions: camera denied/revoked/upload alternatives; own/granted image boundary and no transferable URL; individual deletion only if B4 ships. Motion: camera→preview→real checking→result, reduced-motion equivalent; performance measured. Offline: no server-derived acceptance/measurement invented, secure cache read visibly stale; pending photos explicit opt-in and safe cleanup. Tests: synthetic accepted fixture, corrupted/oversized/EXIF photos, cross-owner/anonymous image denial, session switch, measurement availability/noncomparability, device camera/accessibility/profile metrics. Exit: Observe→Compare complete without provider enablement.

### M3 — Understand → contextual Learn → safe return

Depends on M1/M2. Tasks: integrate PSM v2 sources/summaries/unknowns and history, distinct patient/system/derived/clinician/AI evidence; render `/assistance` metadata/citations/uncertainties; embedded contextual suggestions in Home/history/routine; clinician decision panel from existing projection; return-after-absence refresh and optional contextual question. B5 chat history/consent may ship here as a separately reviewed backend task, not a UI promise.

**DoD:** UI/API/state: source IDs/freshness/units persist from API to screen; no_data/insufficient/stale/change/unknown and clinician-private/no-current-decision correct. Loading/errors: provider disabled/invalid/failure and context failure labelled; deterministic safety available independently. Permission: owner context only, no raw images/sensitive fields sent to model unless new explicit purpose is authorized. Motion: stable evidence expansion/priority update with focus maintained/reduced motion. Offline: historical explanation labelled stale; no generated current assessment from cached safety. Tests: PSM contract fixtures + synthetic source linkage, safety/clinician precedence/provider skip/fail-soft, citation budgets/truncation, Arabic semantic labels. Exit: patient can explain a change with provenance and uncertainty, without autonomous action tools.

### M4 — Change one thing → Routine → Track adherence → Experiment result

Depends on M1/M3 and explicit B3 baseline/experiment outcome decision. Tasks: surface existing RoutineEntry and adherence directly in daily flow; reusable tap-confirm cards, optional swipe later; product inventory/PI linked by stable ID; configure one intervention, activate with frozen reference, report daily use, finish/evaluate; detailed association results and timeline. Gamification and product-card final styling remain open.

**DoD:** UI/API/state: real product→routine→experiment→adherence→evaluation readback; one active intervention constraint, engine version and outcome limitations visible; no unsupported pause/legacy scores promoted. Loading/errors: conflict/invalid eligibility/unknown adherence/unconfirmed finish/refetch handled. Permissions: owner checks, no autonomous medical changes; safety/clinician priority remains visible, clinician advice cannot be superseded by a positive experiment. Motion: completion only after confirmed write; reduced-motion parity and no reward interpreted as safety. Offline: safe drafts/reporting policy; activation/finish/evaluation require fresh online authorization and state; idempotent reporting sync after B2. Tests: existing authority suites + full synthetic vertical contract, wrong-owner/conflict/frozen baseline/source separation/confounders/readback. Exit: patient completes one controlled flow and understands insufficient evidence as a valid outcome.

### M5 — Adapt → preferences/notifications → durable safe offline patient completion

Depends on M1–M4 and B5/B6/B7. Tasks: account-scoped personalization/notifications opt-in, quiet hours, suggested schedule, lock-screen minimized content; encrypted owner cache with freshness and deletion/logout erasure; queue only approved nonmedical drafts/reports with idempotency/version/conflict handling; complete patient RTL/accessibility across all flows; provisional platform builds following launch-order decision. Optional agent broker only after consent/history and an explicit user-confirmed action scope, not as prerequisite for patient usability.

**DoD:** UI/API/state: preference and device-registration readback, clear suggestion vs scheduled delivery, sync pending/confirmed/conflict states. Loading/errors: delivery unavailable/token expired/consent revoked/timezone changes handled. Permissions: push/camera/photo/AI processing separately controllable; cache keys owner-bound and erasure verified; no medical action offline. Motion: all interactions obey global policy/haptics setting; device performance/accessibility gates passed. Offline: reboot cached view works under chosen session policy, wrong account cannot read, reconnect revalidates all writes, deletion not shown complete before server 204. Tests: synthetic settings/scheduling/sync/deletion/restore invariants, denied permissions and reduced motion/TalkBack/VoiceOver. Exit: full patient loop usable in chosen launch platforms without production harness coupling.

### M6 — Clinician workspace → review → consented care communication

After patient completion. Depends on corrected existing nullable mapping, real grant/claim/revoke, B8 messaging/export consent and all privacy invariants. Tasks: typed patient mapping, fresh scoped grants on each request, real QR/deep-link claim, clinical timeline/evidence, visible/private notes and versioned review actions, images/reports/updates chat with secured references, patient contextual surfacing.

**DoD:** UI/API/state: authorized doctor signs in, claims synthetic grant, reviews timeline, records sequenced decision/note, patient sees only authorized visible content; stale sequence 409 handled. Loading/errors: null active experiment/empty patients/revoked/expired/closed/permission denied no crash or data leak. Permissions: authenticated clinician plus active grant, explicit export scope, no client authorization list treated as authority. Motion: calm clinical panels, no delaying urgent triage, reduced-motion parity. Offline: cached clinician data under explicit retention/consent policy; all clinical writes and exports fresh online only. Tests: synthetic doctor/patient E2E, expiry/revoke/cross-patient/privacy/export/attachment/account erasure, screen reader and performance. Exit: end-to-end clinician loop with safety precedence retained, no invented messaging placeholders.

## Explicit backend work packages

| ID | Scope / existing boundary | Required gate / milestone |
|---|---|---|
| B1 | Home observation completion separate from legacy metric baseline; optionally compose safety/visible clinician/priority projections with as-of/version | Persisted report-only observation yields correct today state; scores/baseline still truthful; M1 |
| B2 | General structured check-in idempotency and version/conflict contracts for deferred reporting | Same key/payload returns same ID; different payload conflicts; owner/account deletion races safe; client timeout reconciliation; M1 then M5 |
| B3 | Capture↔observation linkage and report-led baseline/experiment policy | Explicit owner-linked reference, no forged or mixed proxy/score units; define report-only outcome gates without fabricated measurements; M2/M4 |
| B4 | Optional single-photo erasure/image preferences | New reviewed DELETE contract, signed journal before destructive operations, replay/restore/copy coverage; existing account erasure retained; M2 if product requires individual deletion |
| B5 | Durable chat/agent consent and paginated history | New models join account erasure/restore privacy, scoped context and retention, no “complete memory” until retrieval coverage proven; M3/M5 |
| B6 | Notification/personalization/device settings and durable suggested action feed | User opt-in/minimized payloads/timezone/idempotency/revoke, no external provider enablement without later authorization; M5 |
| B7 | Allowlisted explicit agent action broker / sync versioning | Token-derived owner, per-action permission/purpose, confirmation/preconditions/expiry/idempotency; never independent safety/clinical/medical intervention; optional after M5 foundations |
| B8 | Clinician messaging/attachments and explicit export-consent scope | Current generate-qr grants export_consent automatically; separate signed patient choice, per-request role/grant checks, privacy/deletion; M6 |
| B9 | Canonical clinical guidance localization and scalable paginated history | Stable status/reason codes + reviewed localized copy; bounded history cursors rather than unlimited raw lists; M1 foundation/M3 history |

Do not conflate backend work with Flutter tickets. Do not enable Vision to fill B3. Do not expose raw reset codes or configure email as an audit action. Production deployment, migrations, provider enablement and restore drills are separate future authorized milestones.

## Open decision process and measurable completion

Navigation: task-based prototype comparison, then user decision. Adherence/gamification: neutral reporting first; later test opt-in encouraging feedback without guilt or safety implication. Product cards: decide after evidence/unknown/loading/error inventory and practical scan/review tasks. Platform launch order: choose based on actual device/OAuth/camera/signing/accessibility readiness and audience. None is settled by this proposal.

Each milestone produces source-linked UI/API state inventory, regression evidence, synthetic vertical-flow recording, documented limitations and a clean reviewed change. UI appearance alone is not completion. Backend tests alone are not mobile E2E. Production evidence from past rollout remains valuable but does not substitute for staged patient journey certification. Preserve the startup/RTO debt as an independent ops backlog, not a blocker or excuse to mutate production during product audit.
