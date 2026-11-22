# B11 GitHub merge-readiness policy

Status: proposed only. This document does not authorize changing repository
settings, merging, deployment, migration, or Azure access.

## Observed state

- The repository-level rulesets API returned an empty collection.
- The GitHub App can read pull requests, Actions, and rulesets, but the legacy
  branch-protection endpoint returned `403 Resource not accessible by
  integration`. Legacy protection therefore remains unverified, not absent.
- PR #4 is based on `main` at `b995873` and has the three source PR heads in its
  ancestry. Its original three successful check runs all used the job name
  `test`, which is unsuitable as an unambiguous required-check policy.

## Required permissions

Applying or changing this policy requires a repository owner or a collaborator
with GitHub repository **Administration: write** permission. A GitHub App or
fine-grained token used for automation needs **Administration: read and write**
for branch protection or repository rulesets. Pull-request review requests need
**Pull requests: write**; reading checks and workflow runs needs **Actions:
read** and **Checks: read**.

Use a human repository administrator for the first application and verification
of this policy. Do not broaden the current integration merely to bypass the
observed `403`.

## Proposed `main` ruleset

Target only the default branch `main`, set enforcement to active, and require:

1. Changes must be made through a pull request.
2. At least one approving review from a person other than the latest pusher.
3. Dismiss stale approvals when new commits are pushed.
4. Require conversation resolution before merge.
5. Require the branch to be up to date before merge.
6. Require these exact Actions check-run names:
   - `Backend Core / PostgreSQL 18`
   - `Backend B3 / PostgreSQL 18`
   - `Backend B4-B5 / PostgreSQL 18`
7. Block force pushes and branch deletion.
8. Do not grant bypass to ordinary maintainers. Keep any emergency bypass
   limited, auditable, and outside the normal release path.

Require the checks from the GitHub Actions app, not any external status producer
that happens to publish the same text. After applying the policy, verify it with
a disposable pull request; do not test protection by pushing directly to
`main`.

## Merge sequence after approval

1. Land this B11 pull request into the integration branch only after its three
   renamed checks pass and independent review is recorded.
2. Confirm PR #4 points to the resulting integration head (or supersede it with
   one final integration PR if GitHub cannot retarget it safely).
3. Apply the approved `main` protection policy and verify the exact required
   checks appear on the final integration pull request.
4. Obtain a fresh independent approval after the final head is fixed.
5. Merge the final integration PR once. Close PRs #1, #2, and #3 as superseded;
   never merge them again because their heads are already ancestors.
6. Treat merge as source integration only. Deployment, migration, live revision
   reads, and Azure changes remain separately authorized operations.
