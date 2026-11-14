# M2 — Guided Capture, Measurements & Comparison Readiness

Implementation evidence, 14 November 2026. Amr's Flutter feature branch; independent review belongs to Salma. Product M2 is distinct from QA-M2. No formal closure or clinical qualification is asserted.

## A. Verified source and dependency choice

Repository: Hussamwaleed15/Dermaire-Project. Main/base: `b995873f2b76e0c37a08f23fbf40322174aba6fe`.

| PR | State | Head | Base |
|---|---|---|---|
| 6 | Open | `25b0e1f9e04861c98736894d1b31fb02933142cb` | main `b995873f2b76e0c37a08f23fbf40322174aba6fe` |
| 7 | Open | `5d855b499f73866ba6894fe67f950e81ec1b6e51` | PR6 `25b0e1f9e04861c98736894d1b31fb02933142cb` |
| 8 | Open | `a14cd11185816e18befcb90943563346cec5573f` | PR7 `5d855b499f73866ba6894fe67f950e81ec1b6e51` |
| 9 | Open Draft | `83e00a019689b1ff55dc4dc959ab860f9b60c781` | main `b995873f2b76e0c37a08f23fbf40322174aba6fe` |
| 10 | Open Draft | `32cd9f9e062b8b7bf915658af13015e5d685533f` | PR9 `83e00a019689b1ff55dc4dc959ab860f9b60c781` |

Verified via fresh GitHub metadata during execution, not assumed from task SHAs. Branch: `codex/flutter-m2-complete-implementation`, targeting main. All required camera, capture, measurement, private-image and clinical-plan dependencies already exist on main. PR9/10 Home projections and PR6/7/8 authority changes are not dependencies of this read-only history/owner navigation. Neither stack is silently imported, rewritten or activated.

The canonical Master Plan was read from PR9/10 (`app/docs/DERMAIRE_PROJECT_MASTER_PLAN_HANDOFF.md`); it is absent from current main. This report maps §§4–7,9–12,14 to actual code rather than copying the plan onto an unrelated feature branch. App AGENTS.md applies. English-only themes/navigation remain intact.

Contracts inspected read-only: `backend/app/api/v1/captures.py`, `measurements.py`, `backend/app/services/measurement.py` and production Flutter plan/controller/image code. Quality `capture-quality-1.0`; method `measurement-1.0`; clinical plan `clinical-plan-1`; comparison job/input `comparison-job-1` / `comparison-input-1`. No live contract calls.

## B. Original M2 closure matrix

| Requirement | Existing implementation | Verified gap | Change | Evidence | Final status | External dependency |
|---|---|---|---|---|---|---|
| Real camera or honest upload | CameraSession, NativeCameraPort, GuidedCameraScreen; real front-camera adapter, JPEG/PNG picker | No new safe Flutter gap demonstrated | Preserved | guided_capture/native_camera_port suites | IMPLEMENTED — NEEDS EXTERNAL QUALIFICATION | Physical Android/iOS permissions, camera, picker, lifecycle and memory qualification |
| Quality/permission states | Server quality checks; accepted/rejected/unsupported; settings guidance; unknown pose/lighting; upload uncertainty | No new quality algorithm or permission gap demonstrated | Preserve; explicitly label malformed embedded estimates | capture_quality/guided_capture suites; malformed model regressions | IMPLEMENTED — NEEDS EXTERNAL QUALIFICATION | Quality/model/clinical validity and device behavior |
| Real measurements/provenance | Strict two-proxy parser and result UI; fuller source copy only in detail | Unequal provenance, omitted reason/meaning/comparison metadata | Shared MeasurementEvidence for result/detail/history; typed optional metadata; distinct absent/unsupported/non-comparable | New parser/widget tests plus guided_capture | IMPLEMENTED AND VERIFIED | Only nonclinical image proxies; no medical accuracy or trend inference |
| Authenticated private images | Owner endpoint, scoped plan reads, before/after original authority checks, bounded in-memory decoded leases, no public ImageProvider/cache | No new image access violation demonstrated | Preserve; new history never downloads images automatically | private_capture_history/private_capture_image_limits/wave_comparison | IMPLEMENTED — NEEDS EXTERNAL QUALIFICATION | Live storage/authorization and mobile privacy/memory qualification |
| History/non-comparable | Bounded receipt/image timeline; typed strict measurements; optional measurement comparison ignored | No longitudinal numeric evidence view; identity-reused detail could retain prior controller | Five-record bounded read-only measurement history, per-row failure/retry, provenance, explicit no trend, resource rebinding | Real controller two nonempty batches, partial/errors/timeout/switch/disposal/rebinding and large-text tests | IMPLEMENTED AND VERIFIED | Latest100 only, no cursor; comparison quality dimensions remain unknown |
| Plan-linked comparison preparation | Production clinical plan images, baseline/follow-up association, explicit schedule, jobs/review/unavailable states; separate prepared comparison architecture | Missing patient path to linked capture detail and account measurement chronology | Original baseline/follow-up IDs passed to fresh owner reads; separate account history; no association inferred; no doctor owner-route exposure | Four new plan navigation widget tests + wave_comparison/plans + comparison_architecture | IMPLEMENTED — NEEDS EXTERNAL QUALIFICATION | Actual inference/artifact transport and clinical validation remain unavailable; F8 authority rollout separate |

Four newly identified safely code-addressable gaps completed: longitudinal view, complete consistent evidence, capture-route rebinding, plan evidence navigation. Existing camera/quality/image/job engines were not duplicated.

## C. Actual implementation and acceptance

### C1. Bounded chronological measurement history (M2-C/D/H)

`app/lib/capture/capture_history_controller.dart`: MeasurementHistoryController reuses the existing repository and owner/session generation checks. GET latest100 metadata is ordered by server receipt descending then ID descending. The initial batch and each explicit next batch cover at most five capture records, reading accepted captures sequentially. Rejected captures never request a measurement. No image fetch, POST generation, storage, chart, subtraction, score, baseline selection or clinical claim is introduced.

Each row independently preserves successful measurement, server-recorded unavailable/failed/insufficient_quality values, missing404, conflict409, authorization401/403, timeout, transport/server failure or unsupported response. Retrying a failed row rereads only that measurement. Numeric zero remains zero; null never becomes zero. Valid responses must match original capture ID and request fingerprint. Refresh clears previous rows and fences overlapping responses; disposal/account/safety/session loss clears measurements and prevents subsequent batch calls/publishing.

`app/lib/capture/measurement_history_screen.dart`: patient-readable date/source/quality and expandable actual evidence, explicit further reads, retry, loading/empty/window-boundary states. Clearly states latest100 is not lifetime history and client-reported source/UTC server receipt is not camera time. No private images requested until opening an independently authorized detail screen. Background disposes private metadata/controller; resume rereads only within the same session. Repository/state rebinding replaces the prior controller. Existing themes/components, reduced-motion expansion and narrow200% readability retained.

### C2. Consistent evidence and trustworthy unsupported states (M2-B/C/F)

`app/lib/capture/guided_capture_models.dart`: retain validated provenance, optional reason/meaning and independently parsed comparison metadata. Missing comparison is absent/unknown. Supported `not_comparable` requires a reason and no deltas/comparable predecessor. A contradictory or unsupported claim cannot fabricate change results or erase otherwise valid measurement evidence. Current backend leaves required pose/lighting dimensions unknown; no numeric comparison result is rendered.

`app/lib/capture/measurement_evidence.dart`: same method/version, measurement/source ID, timestamp, region, provenance, real value/unit, status/reason/meaning and limitations in immediate capture results, details and history. Measured versus server-recorded unavailability remains explicit. `guided_camera_screen.dart` uses it and explicitly explains malformed embedded measurements without revoking the confirmed capture or inventing values. `capture_history_models.dart` supplies distinct read failures; detail controller now uses these rather than collapsing all errors into generic unavailable.

### C3. Resource identity and navigation (M2-E/G/H)

`app/lib/capture/capture_history_screen.dart`: new measurement-history entry; didUpdateWidget replaces/disposes prior history/detail controllers on resource/repository/state identity changes. A late old detail cannot replace the new requested capture. Measurement evidence duplication removed in favor of the shared widget.

`app/lib/plans/plan_ui.dart`: only a current patient view with application state can open its exact baseline/follow-up capture IDs or account-wide measurement history. Current/revision guards retained. Fresh detail reads authorize the owner resource; no history row is attached to the plan. Doctors keep the existing original-grant-bound PlanImagePanel and cannot use patient owner endpoints. Return/background behavior remains within existing PrivateView authorization refresh. No shell redesign, clinical write, plan timing or evaluation algorithm added.

New regression files: `app/test/m2_measurement_history_test.dart` (23), `app/test/m2_plan_navigation_test.dart` (4). All synthetic; no original assertions removed or weakened.

## D. Validation

Flutter3.44.8 stable, framework `058e0af2c2b57e369d905a03ac9748b0ebf543c6`, Dart3.12.2.

| Command (from app) | Result | Exit |
|---|---|---|
| `flutter test --no-pub --reporter expanded test/m2_measurement_history_test.dart test/m2_plan_navigation_test.dart` | 27 passed,0 failed,0 skipped | 0 |
| `flutter test --no-pub --reporter expanded test/m2_measurement_history_test.dart test/m2_plan_navigation_test.dart test/guided_capture_test.dart test/native_camera_port_test.dart test/private_capture_history_test.dart test/private_capture_image_limits_test.dart test/capture_quality_test.dart test/comparison_architecture_test.dart test/wave_comparison_test.dart test/wave_plans_test.dart` | 404 passed,0 failed,0 skipped | 0 |
| `flutter test --no-pub --reporter expanded` | 2281 passed,0 failed,0 skipped | 0 |
| `flutter analyze --no-pub` | No issues | 0 |
| `git diff --check` | Clean | 0 |

Initial widget tests needed real scroll/frame settling because the shared page lazily builds offscreen content; corrected tests now interact with visible controls. An initial related command referenced nonexistent comparison_test.dart; corrected to comparison_architecture_test.dart and reran successfully. No production behavior/assertions weakened to obtain green results.

Synthetic HTTP remains denied by test/flutter_test_config.dart and isolated fixtures; no OAuth/live API/patient/clinical/provider calls. Dependency/native/Backend/Tester changes: none. No production build/deploy.

Compatibility evidence: separate disposable archives of exact PR10 and PR8 heads with main→M2 app delta, clean git-apply checks and identical pubspec/lockfile; shared cached host tooling, no original refs mutated. Both ran `flutter test --no-pub --reporter expanded` with exit0: PR10+M2 **2334 passed**, PR8+M2 **2369 passed**, each0 failed/0 skipped. This is source/test compatibility, not native builds, live Backend compatibility, merge approval or clinical validation.

CI: main/M2 has no active workflow under .github/workflows. The F8 workflow belongs to the unmerged PR8 stack. Query the actual new head/applicable synthetic merge after Draft PR creation; do not use PR8 green checks as M2 CI qualification. No M2 Actions success is asserted here.

## E. Git delivery

Branch/base as in A. Source commits:
- `7d419a2d9f1bcd2c2cf923f3af237fbfa9b42ce3` — feat(flutter): add bounded measurement history and verified capture evidence.
- `9511825253f16f304ca6bbc5eb7d55b7f31c53a4` — feat(flutter): link patient plans to original capture evidence and history.

Closeout docs commit, exact remote verification, Draft PR and clean status are recorded in the final delivery supplement. Published as verified local Git identity Amr-A-Abdallah. No other PR branch/main is changed; no force push, merge, approval or milestone closure.

## F. External handoff

See M2_EXTERNAL_DEPENDENCIES.md for exact contracts and owners. No Backend issue/message was sent.

## G. Readiness axes

1. Flutter: all four demonstrated safely addressable gaps implemented and host-tested; existing workstreams retained.
2. Flutter integration: local synthetic main baseline passes; M1/F8 source compatibility separately qualified, not merged/activated.
3. Physical devices: pending camera/permission/settings/picker/navigation/background/memory/privacy qualification on supported Android/iOS.
4. Live Backend: pending nonproduction coordinated contract qualification; no live requests authorized or run.
5. AI/clinical: no validated inference or clinical change assessment; remain explicitly unavailable. Proxy values have no diagnostic/medical accuracy claim.
6. Independent QA: PENDING SALMA REVIEW.
7. Product M2: PENDING FORMAL CLOSURE, external qualification is outstanding.

## H. Real remaining M2 dependencies

Physical-device qualification; actual live private-image/measurement/plan authorization compatibility; unknown quality/comparison dimensions and absent validated inference/artifacts/clinical validity; coordinated policy/grant rollout where applicable. Latest100 bounded read-only history is implemented; cursor-based lifetime history is an enhancement requiring a server contract, not silently simulated pagination. No additional independent safe Flutter gap was demonstrated in this review.

## I. Next legitimate development

M3 — PSM, Understand & Contextual Learning: reconcile existing PSM v2 and evidence-card source/freshness/uncertainty behavior against the canonical Master Plan, then implement only demonstrated supported gaps (including return-after-absence). Existing M3 work is not assumed absent. No autonomous tools or invented F9. No M3 implementation started here.

**M2 Flutter implementation:** COMPLETE (supported source scope; external qualifications outstanding)

**M2 newly identified code-addressable gaps:** 4 completed / 4 identified

**M2 external blockers:** physical Android/iOS qualification; live Backend/storage/authority compatibility; validated image/comparison model, artifact transport and clinical qualification; coordinated authorized rollout.

**Focused tests:** PASS —27

**Full Flutter tests:** PASS —2281

**Flutter analyze:** PASS —no issues

**Git delivery:** see final delivery supplement

**Draft PR:** see final delivery supplement

**Independent QA:** PENDING SALMA REVIEW

**Product milestone M2:** PENDING FORMAL CLOSURE
