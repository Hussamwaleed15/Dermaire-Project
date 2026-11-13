# Flutter F8 CI and merge readiness

2026-11-13. Amr A. Abdallah / Amr-A-Abdallah. Starting branch
codex/flutter-f8-2-to-5-integration at
5d855b499f73866ba6894fe67f950e81ec1b6e51. Separate feature branch:
codex/flutter-f8-ci-readiness, stacked on PR7 without rewriting PR6/7.

## Why checks are absent

PR6 is open at25b0e1f9e04861c98736894d1b31fb02933142cb, base main.
PR7 is open at5d855b499f73866ba6894fe67f950e81ec1b6e51, base the PR6 branch.
Their Flutter ancestry has no .github/workflows directory. Backend workflows
live in separate unmerged Backend branches, are not Flutter gates and were not
modified. Successful local tests are not GitHub checks or independent approval.

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

## Reproducible proposed gate

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
No Linux/GitHub CI execution was triggered. The initial four ordering fixtures
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
