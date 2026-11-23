# QA-M1 P3 implementation evidence (PR #8)

## Current evidence checkpoint — 23 November 2026

Task DERMAIRE-FLUTTER-QA-M1-02-FINAL-CLOSURE. Documentation-only correction
by Amr A. Abdallah / Amr-A-Abdallah; no source, tests or workflow behavior changed.
Before this documentation correction, the verified PR8 HEAD is
`12d88727bb7b00aac1be5ffbc309336c3e169ca8`; base PR7 is
`a5a3f2e8b1974a979214e463308c114cc09ac09c`.
These are the pre-correction revisions, not a claim that a subsequent docs
commit has already passed CI. The final current HEAD and its own run/job/merge
revision evidence are maintained in PR8's description after push, avoiding a
self-referential documentation/CI update cycle.

Latest independently verified Flutter CI supplied with Amr's QA handoff:
[run45071674083](https://github.com/Hussamwaleed15/Dermaire-Project/actions/runs/45071674083).
GitHub API rechecked its head_sha as `12d88727bb7b00aac1be5ffbc309336c3e169ca8`,
completed/success, with successful `Flutter source / current-pr-head` and
`Flutter source / current-pr-merge` jobs. A run's head_sha identifies the PR
head; it does not itself identify the checked-out synthetic merge commit.
This historical run does not validate the new documentation commit.

- QA-M1-01: PASS, independently verified previously according to the supplied
  Salma Ahmed re-verification handoff (controller12/12, related71/71,
  full2342/2342 and analyzer PASS). No tests are reopened or reimplemented.
- QA-M1-02: documentation remediation implemented; pending Salma's final
  independent re-verification. Not formally approved or CLOSED.
- Public GitHub comments retrieved before this correction still contain the
  older open findings; no submitted formal reviews were returned. The supplied
  latest QA result and public historical comments are separate evidence.
- Active workflow `.github/workflows/flutter-f8.yml` tests dynamic PR head and
  synthetic merge; app/docs changes match its path filter. Workflow unchanged.
- CI success is source evidence, not QA approval, native/device, live Backend,
  staging, clinical, provider or production qualification. Policy stays off.
- PR8 remains dependent on PR6/PR7 integration, current required Backend and
  Flutter checks and independent review. Salma decides QA approval; Hussam
  owns final merge authorization. No merge/retarget/protection change authorized.

Earlier sections below are dated historical evidence. Their heads, base
snapshots, test totals and runs43418894776/43613490447 must not be interpreted
as the current PR HEAD or as qualification of later commits.

## Historical implementation record (preserved)

2026-11-14. Amr A. Abdallah. Repository Hussamwaleed15/Dermaire-Project,
branch codex/flutter-f8-ci-readiness, base codex/flutter-f8-2-to-5-integration.
Fetched and fast-forwarded cleanly from 401edbf to actual remote/PR head
16cdd38d7f27dc295f25d2243fba08aa6a530417 before editing. No merge/approval,
QA sign-off, Backend/native/Tester/service changes or workflow edits.

## QA-M1-01

Added test/f8_clinician_requests_controller_test.dart: actual
ClinicianRequestsController with the existing injected HTTP fixture and real
ApiService validation. Every transport call invokes expectHost; only the
synthetic .invalid test host is accepted. No real login/OAuth or Backend calls.
The initial page contains (z,03), (y,02); the second contains (x,02), (w,01),
with fixed UTC preview timestamps and matching five-minute preview validity.
The original grant expiry remains future-bounded via the existing fixture.
Both pages are nonempty. A Completer controls each delayed response, not timing
assumptions about network delivery. Notifications capture exact busy transitions.

Exact added test names:

- controller appends two nonempty pages with boundary ties and busy transitions
- controller rejects missing timestamp across pagination and clears private rows
- controller rejects invalid timestamp across pagination and clears private rows
- controller rejects ascending time across pagination and clears private rows
- controller rejects duplicate id across pagination and clears private rows
- controller rejects equal tuple across pagination and clears private rows
- controller rejects ascending tie across pagination and clears private rows
- controller recovers from initial API failure
- controller recovers from pagination API failure
- controller hide wipes rows and rejects late page
- controller session change wipes rows and rejects late page
- controller dispose wipes rows and rejects late page

Methods exercised: refresh, more, hide, show, dispose and actual session-change
notification through ApiService.init. Observable assertions cover requests IDs
and timestamp ties, append order, no drops/duplicates, next cursor, request query,
no extra fetch while busy/exhausted, busy true/false notifications, error state,
fail-closed clearing, refresh-based recovery and late-page rejection. HTTP503 is
tested on initial load and pagination. Invalid responses are exercised through
the controller rather than calling the tuple helper.

Existing contract intentionally wipes all rows/cursors on pagination failure;
recovery is refresh then more, not automatic replay of a lost cursor. Disposal
has no live-view busy-state contract; privacy and stale-row prevention are
asserted instead. Session generation invalidation uses init, avoiding real
logout calls. No production bug was exposed, and production source is unchanged.
Authority-expiry timers, every HTTP error class and native lifecycle/device E2E
are not newly qualified by these targeted tests; existing suite remains intact.

## QA-M1-02

Inspected .github/workflows/flutter-f8.yml at the fetched head: active PR event
workflow, ubuntu-24.04, current-pr-head/current-pr-merge matrix, pinned Flutter
and action commit, lockfile enforcement, analyzer and full synthetic suite.
Corrected FLUTTER_F8_CI_MERGE_READINESS.md sections formerly claiming absence or
no execution. GitHub API independently confirms run 43418894776 completed with
success at exact head 16cdd38d7f27dc295f25d2243fba08aa6a530417, both matrix jobs
successful:
https://github.com/Hussamwaleed15/Dermaire-Project/actions/runs/43418894776

PR description must distinguish committed/configured, triggered, and completed
success; old run success does not qualify a new commit. Final exact-head Actions
evidence and publication SHA are supplied in the delivery report after push.
Independent review, current-head checks and authorized merge remain prerequisites.
No CI execution is represented as independent QA approval.

## Validation and QA handoff

Commands from app: focused12 PASS, relevant71 PASS, full2342 PASS
(0 failed, 0 skipped); analyzer clean. All final commands exited0;
git diff --check also exited0. Final post-push CI is recorded in delivery report:

```text
flutter test --no-pub test/f8_clinician_requests_controller_test.dart --reporter expanded
flutter test --no-pub test/f8_clinician_requests_controller_test.dart test/f8_ci_order_test.dart test/f8_final_source_review_test.dart test/wave_agent_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
git diff --check
```

Initial test compilation caught an inherited fixture member-name collision;
renamed only the new fixture method and reran successfully. No validation was
weakened. No dependencies changed. QA should independently rerun controller
tests, inspect exact-head matrix results, verify fail-closed wipe/recovery and
confirm PR description matches actual run evidence.

**Implementation status:** COMPLETE (subject to recorded post-push checks)

**QA-M1-01:** READY FOR RE-VERIFICATION

**QA-M1-02:** READY FOR RE-VERIFICATION

**QA-M1 overall:** PENDING INDEPENDENT QA SIGN-OFF
