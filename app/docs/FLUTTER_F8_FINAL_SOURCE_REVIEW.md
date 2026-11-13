# Flutter F8 final source review and merge readiness

2026-11-13. Reviewer/executor: Codex for Amr A. Abdallah.
This is source review and synthetic regression evidence, not independent human
approval, device validation or deployment authorization.

## Baseline and findings

PR6 remains open at25b0e1f9e04861c98736894d1b31fb02933142cb, base main.
PR7 remains stacked on PR6; starting head
f7904ca143097d479e85422bff3288c8f1efaf25. Worktree was clean.
Existing unrelated historical worktree was preserved.

Actual defects repaired on the PR7 feature branch:

1. F8-3 discovery accepted unsupported/duplicate scopes and unordered session
   summaries. It now rejects those responses and checks expiry/id descending
   ordering across loaded pages. Discovery and doctor requests previously rejected
   only immediately repeated cursors: empty pages could cycle A→B→A. Track seen
   cursors, clear them on refresh/invalidation and reject cycles. Retain bounded
   loaded-row behavior. Tests cover malformed/private metadata, duplicate/order,
   HTTP401/403/404/409/410/422, session and doctor cursor cycles, delayed logout and
   account switch. An independent full refresh resets cursor history; legitimate
   repeated first-page reads are not rejected.
2. F8-2 Dart String.length counted UTF16 code units rather than Backend Python
   Unicode characters. Both reset UI and API now count runes, preserving original
   password content. Tests with4/8/128/129 supplementary characters verify the
   same acceptance boundaries, without printing passwords/codes.
3. F8-4 readback checked read/unread value but could accept a page older than its
   acknowledged mutation revision. It now requires current readback revision at
   least the mutation receipt revision. A regression returns an ahead receipt and
   verifies no success outcome is presented from the older current page.

No fabricated issues/commits for F8-1 or F8-5 were introduced.

## Milestone review

F8-1: request grant/key frozen in original intent; response-only explicit binding
checked case-insensitively; no response header sent as a request precondition.
Same-body/key/grant checks constrain deliberate retries. Unknown responses retain
identity, with no automatic POST/re-key. Existing receipt matching proves exact
persisted grant/actor/patient/payload/sequence, not retrospective observation of
the explicit response header. Current authorization checks bracket historical
receipt/PHI reads. Existing F7/F8 tests cover late responses, replacements, logout,
expiry and CAS. That evidentiary distinction remains a documented limitation.

F8-2: typed metadata, HTTPS/no redirects, document size/time bounds, exact-byte
SHA256 before UTF8 display, reviewed version and authoritative server acceptance.
The rollout flag remains false by default. No approved policy text/URL/hash/version
or rollout authorization was supplied; enabling the gate and qualifying it against
an approved document remain owner/Hussam dependencies. Legacy compatibility is an
explicit release choice, not permission to activate enforcement independently.
Do not enable server/client policy rollout out of coordination. Logout/deletion
remain available. Reset generic responses discard debug/account details; duplicate
UI submissions are blocked and late success cannot clear a newer account session.

F8-3: authenticated discovery metadata never establishes authority from an id;
selected sessions are re-read through current authorization. Doctor patient_ref
uses only returned current_original_grant binding, then reauthorizes original
grant before the existing clinician record route. Missing ref does not create a
patient target. Unsupported inference remains unavailable. Negative coverage was
previously too narrow; the added tests address specific new discovery guards.

F8-4: target.thread_id is used only from a server-authorized message target with
matching message_id. Conversation is re-read with current participant authority.
Missing legacy target opens an independently authorized list, never a guessed
private thread. expected_revision is sent from the loaded notification.412 performs
refresh without replay; missing revision blocks mutation; busy and generation
guards fence duplicate taps and old-account responses. Read state != push delivery.

F8-5: distinct original cancellation key/revision/job/grant, retained on uncertain
outcomes, blocks subsequent plan mutations. Receipt lookup compares original job
and reads current authorization/plan/evaluation separately. Unknown/expired/erased/
denied evidence does not permit a replacement. Backend revision/CAS guards worker
races; host tests do not reproduce a live worker transaction. No inference claim.

## Verification

Added20 focused negative/boundary tests. Focused review/policy/integration/F8-1:
72 passed. Full Flutter:2326 passed,0 failed,0 skipped. Analyzer and diff-check
clean. Published SHA is recorded in the delivery report. Commands: focused final review/policy/
integration/F8-1 tests; flutter analyze --no-pub; full flutter test --no-pub;
git diff --check. All HTTP synthetic, no patient data/live services.

No GitHub Actions runs were listed for the starting PR7 head and no submitted
reviews were listed for PR6/PR7. This branch has no local .github/workflows
directory. Local tests must not be described as remote CI or independent approval.
Repeat checks on new heads and satisfy whatever protection/review rules apply;
absence of checks is not permission to bypass them.

## Exact proposed merge sequence (not executed)

1. Independently review PR6 at its exact current head, require applicable checks.
   Then an authorized maintainer may merge PR6 into main. Prefer a merge preserving
   its commit ancestry for this stack. Preserve the PR6 base branch until PR7
   has been safely retargeted. No merge is authorized by this review.
2. Verify main contains the approved F8-1 content/commit. Retarget PR7 from the
   F8-1 branch to main; inspect the entire recomputed diff and all changed files.
   It must contain only intended F8-2–5/review fixes, without Backend changes.
3. If PR6 was squash/rebase merged and ancestry diverges, reconcile main into
   PR7 using a normal reviewed merge (or a separately approved clean restack).
   Do not force-push/rewrite the existing branches. Verify F8-1 is not duplicated
   in the resulting diff. This is a conditional future step, not performed here.
4. Rerun relevant/full tests and required CI on the reconciled head and current
   base, obtain independent review/approval again for changed heads/diffs, then
   an authorized maintainer may merge PR7. Never carry stale approvals forward.
5. Backend PR4/5 merge/deployment and policy release remain Hussam/owner work.
   Flutter merging does not deploy a compatible API or authorize migrations.

F8-1/3/4/5 are ready for independent source review after the fixes. F8-2 remains
PARTIAL for policy rollout approval/document qualification. All live integration,
physical-device/native storage/camera/OAuth/Push and clinical-model qualification
remain UNVERIFIED; F8-6 postponed. F9 is not started. Resolve source review/merge
and policy rollout decisions first; do not treat this report as F9/production
authorization. No Backend/Azure/native/Tester/DB/production/global Git changes.
