# F6d-3 — Original experiment lifecycle receipts

2026-10-18. Builds on routine receiptscdfc8da32c5dd4b81c913552e1f7cc98fdbb4c81.
Inspected real experiments API and ConfigurationAttempt service before editing.

Create/edit/activate/finish/DELETE-cancel/evaluate now use an exact key, immutable
original body, parent If-Match and optional linked Routine-If-Match. Draft Cancel
in the current UI still uses POST finish with status cancelled; DELETE cancel has
a separate operation identity. Activated definitions remain immutable and legacy
v2 toggle-pause remains unavailable. No routine/experiment behavior is rebuilt.

Normal activation still requires the already implemented fresh routine review and
both original revisions. Recovery first GETs the exact configuration attempt;
unknown permits only explicit original replay, not a new review silently replacing
the payload/preconditions. Original replay can precede current CAS/business checks
on the backend, as required to reconcile a committed activation. If the original
request did not commit and routine changed, its unchanged header is rejected412,
not upgraded to the new version. An already uncertain operation remains locked,
even after that rejection, until source-backed reconciliation resolves it.

ConfigurationReceipt common metadata stays limited to its actual shared SQL
contract. Experiment validates owned original ExperimentOut and exact identity/
revision; evaluation validates original EvaluationOut bound to the parent ID while
resource_revision is the parent version, not a fabricated evaluation revision.
Current owned experiment is read independently and the controller refreshes its
actual list; historical active/draft/evaluation snapshots never replace newer
current terminal state or another later result. Missing current rows are not
recreated. Keyed DELETE sends no invented JSON body.

The existing experiment screen exposes original check/retry and explicit expired/
erased receipt review. No replay occurs merely from refreshing. Late session
responses cannot restore private records; replacement operations remain blocked.
Known successful individual response/readback followed by a failed list refresh
marks stale data without orphaning an uncertain key. A first definitive validation
rejection similarly does not permanently lock a creation; a separately reviewed new
request can use a new identity. Routine configuration applies the same correction;
adherence409 uncertainty remains unchanged.

31 experiment regressions +1 routine validation regression: every lifecycle op
before/after loss; exact body/key/pair of headers; changed routine412 with old
headers; original versus newer terminal state; wrong actor/evaluation/parent
revision;401/403/404/409/410/412/422/428/503; expired/erased review; late logout;
actual evaluation recovery UI; definite create422 then reviewed new intent.
Existing DELETE fixture now models the real empty body while retaining revision
assertions. No backend E2E, process-persistence or mobile-device claim.

Final gate: pub get succeeded; analyzer clean; all1713 Flutter tests passed (+32).
