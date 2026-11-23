# Flutter source verification infrastructure

This document covers only the GitHub Actions infrastructure in
`.github/workflows/flutter-source-verification.yml`. It does not change or define
product behavior, clinical policy, deployment policy, or the project Master Plan.

## Scope and evidence

For a pull request targeting `main` that changes `app/**` or the workflow itself,
the workflow creates two independent jobs:

- `pr-head` checks out and verifies `github.event.pull_request.head.sha`.
- `synthetic-merge` checks out and verifies `github.sha`, the synthetic merge
  revision created by GitHub for the pull request event.

Each job records the expected and checked-out SHA in its job summary, installs
Flutter 3.44.8 at commit `058e0af2c2b57e369d905a03ac9748b0ebf543c6`,
verifies Dart 3.12.2, resolves only the committed lockfile, runs
`flutter analyze --no-pub`, runs the complete `flutter test --no-pub` suite, and
fails if dependency resolution or the checks alter tracked source.

## Security model

- The workflow uses `pull_request`, not `pull_request_target`.
- The token has only `contents: read`; checkout does not persist credentials.
- No secrets are referenced or provided to jobs.
- The only third-party action is `actions/checkout`, pinned to a reviewed commit.
- Fork pull requests therefore run untrusted Flutter source without repository
  secrets or a write-capable token. Maintainers must still review workflow changes
  as code because tests and build tooling execute pull-request content.
- Concurrency cancels superseded runs for the same pull request or branch.

## Bootstrap limitation

GitHub evaluates a `pull_request` workflow from the pull request's base branch.
Consequently, the infrastructure pull request that first introduces this file
cannot provide hosted evidence from this workflow for itself. Local YAML and
logic validation is useful, but it is not a substitute for GitHub-hosted evidence.
The gate becomes authoritative only after this infrastructure change is reviewed
and merged into `main`.

## Post-merge procedure for existing Flutter pull requests

1. Confirm the infrastructure change is present on `main`.
2. Safely trigger a new `pull_request` event for PR #6 by reopening it if closed,
   or by synchronizing its existing branch without changing its intended source.
3. Confirm both matrix jobs were created from the workflow on `main`.
4. Confirm the `pr-head` summary names PR #6 head
   `0d9a4c46fc577c17d48874061dbdc737abe81f4f` (unless the PR was intentionally
   updated) and the `synthetic-merge` summary names GitHub's newly generated SHA.
5. Require both jobs to succeed before using them as merge evidence. Record the
   run URLs and both checked-out SHAs.
6. Repeat the same process for PR #7 and PR #8 when they target `main` and are
   ready for independent verification. Evidence from one pull request does not
   qualify another.

Reopening or synchronizing a pull request is only a trigger. It is not approval,
does not alter review requirements, and does not authorize merging.
