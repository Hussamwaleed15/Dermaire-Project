# Flutter F8 CI and merge readiness

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

2026-11-13. Amr A. Abdallah / Amr-A-Abdallah. Starting branch
codex/flutter-f8-2-to-5-integration at
5d855b499f73866ba6894fe67f950e81ec1b6e51. Separate feature branch:
codex/flutter-f8-ci-readiness, stacked on PR7 without rewriting PR6/7.

## Workflow coverage and observed CI

PR6 is open at25b0e1f9e04861c98736894d1b31fb02933142cb, base main.
PR7 is open at5d855b499f73866ba6894fe67f950e81ec1b6e51, base the PR6 branch.
PR8 now commits .github/workflows/flutter-f8.yml (activation head
16cdd38d7f27dc295f25d2243fba08aa6a530417). Backend workflows remain separate
and were not modified. Successful local tests are not independent approval.

GitHub confirms run 43418894776 completed successfully for that exact head:
https://github.com/Hussamwaleed15/Dermaire-Project/actions/runs/43418894776
Configured, triggered and successfully completed are distinct states. This prior
run does not qualify subsequent remediation commits; inspect their own runs.

## CI activation and ownership correction

GitHub repository metadata confirms visibility=public. Official documentation
states standard GitHub-hosted runners in public repositories are free:
https://docs.github.com/en/actions/concepts/billing-and-usage
https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run
Larger runners are billed; none is proposed. No cache/artifact upload or paid
service is proposed. Reassess if visibility or runner type changes.

The original proposal and Flutter source changes were authored by
Amr-A-Abdallah. On 2026-11-13 Hussam explicitly authorized the CI-only correction
and test execution on PR8, without merge. The correction is authored and
published under Hussam's configured Git identity; it is not attributed to Amr.
No repository settings, branch protection, required checks or billing settings
are changed. No budget increase, paid runner or protection bypass is requested.

## Configured source gate

Standard ubuntu-24.04 runner,25min timeout, contents:read, no stored checkout
credentials, no secrets, no pull_request_target, no native/device build.
Checkout is pinned to a full action commit. Flutter source is pinned to
058e0af2c2b57e369d905a03ac9748b0ebf543c6 (Flutter3.44.8, bundled Dart3.12.2).
Dependency resolution uses committed pubspec.lock with --enforce-lockfile.
Analyze --no-pub, full test --no-pub and diff integrity are mandatory. The suite
includes existing F8 security/privacy tests and test HTTP binding/invalid-host
guards. Setup may download SDK/pub/native assets; no command invokes OAuth,
patient/Backend/Azure/Push/email/model services. This is source verification.

PR runs test two dynamic revisions: GitHub's current PR merge result and the
current PR head SHA. The `edited` activity covers a base retarget when the branch
and path filters still match; a retarget alone must not be treated as green until
the resulting run is observed. A push to `main` tests the exact pushed SHA after
a future authorized merge. Historic PR6/PR7 snapshot jobs were removed because
they were stale evidence and tripled every run. PR8 checks still do NOT attach
checks to the original PR6/PR7 heads; their final reconciled heads need their own
applicable workflow/check evidence later.

Linux feasibility: installed sqlite3-3.5.2 native hooks include Linux x64
SQLCipher assets with pinned hashes; pubspec selects source:sqlcipher. Host key
platforms are mocked in unit tests. No source evidence requires macOS for this
suite. Linux results are recorded from GitHub Actions after each authorized PR8
run. Until a run completes, feasibility remains source-grounded. If Linux fails,
inspect actual native dependency evidence before proposing standard macOS;
do not skip SQLCipher/security cases or substitute plaintext SQLite.

## Actual contract correction

Agent sessions already use (expires_at,id) descending and were reviewed against
Backend agent_platform.sessions. Doctor requests use (previewed_at,id) descending
in Backend request_inbox, but Flutter did not validate that tuple ordering across
pages. Added verifyAgentRequestOrder and applied it to the concatenation of
retained and new rows, or just fresh rows on refresh. ID-only ordering is NOT used.
Equal timestamps require descending IDs. Four tests independently cover timestamp
priority, ID-only false ordering, tie ordering, and duplicates.

Other F8 contracts were rechecked with current source and prior unchanged
Backend integration handoffs: frozen original grant/explicit response binding;
policy exact-byte proof/default-off rollout and reset bounds; account/role and
patient_ref isolation; notification target/CAS/readback revision; original job/
key/revision cancellation and historical-vs-current receipt distinction.
No speculative changes or Backend patches were made.

## Merge plan, not executed

Local final verification: focused24 passed; full2330 passed,0 failed,0 skipped;
flutter analyze --no-pub clean; git diff --check clean; proposal YAML parsed.
That historical local verification preceded activation. Linux/GitHub execution
is now confirmed by the exact-head run linked above. The initial four ordering fixtures
were corrected to preserve Backend's five-minute preview validity invariant;
no production assertion was weakened.

1. Independently review the new tuple-order fix/proposal PR. If approved, merge
   it into the PR7 feature branch and rerun applicable checks on the new head.
2. Independently review PR6 exact head, require applicable checks/evidence, and
   only an authorized maintainer may merge it to main. Prefer preserved ancestry;
   keep its branch until PR7 is safely retargeted.
3. Verify main includes approved F8-1, retarget PR7 to main and inspect the entire
   diff for intended Flutter-only changes. If squash/rebase diverged ancestry,
   reconcile with a normal reviewed merge or separately authorized clean restack;
   never force-push existing history or duplicate F8-1 changes.
4. Execute analyze/full tests/required CI for final heads and base combinations. Obtain
   independent review of PR7's final head, not stale approvals, then only an
   authorized maintainer may merge it.
5. Backend merge/deployment, approved policy document and coordinated rollout
   remain Hussam/owner tasks. No Flutter merge proves production API compatibility.

F8 source/host work is reviewable; GitHub CI is green only for the exact SHAs
reported by completed runs. F8-2 policy rollout remains PARTIAL and default-off.
F8-6 physical-device/camera/OAuth/Keychain/Keystore/Push/recovery validation remains
deferred; no staging E2E, production API or clinical AI qualification. No F9 work
started. Recommended next: close CI/review gates, then define F9 as a bounded
patient/clinician journey against an explicitly authorized isolated Backend;
do not infer real AI/Push or device readiness.
