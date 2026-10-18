# F6-M execution ledger —2026-10-18

Start a93ab02097af15027e9b1b0ab3913f10b14b6b89; correct origin fetch/push,
clean main, fetch0/0. Read AGENTS/current reports and actual source. Baseline:
pub get/analyze clean, full1885. Flutter-only, no native/backend/Tester/live calls.

Sequence: M1 Agent UX; M2 inbox/reminders; M3 original evaluation history;
M4 prepend scroll; M5 privacy races; M6 typed journal/proposal; M7 workflows;
M8 device evidence. Each verified increment gets full gates and normal push.

## M1 Agent workspace — DONE bounded

Actual agent_platform routes/session/action schemas and controller inspected.
GET sessions still needs an ID; doctor requests still bounded100/no cursor and no
patient reference. No synthetic discovery or patient navigation added.

Added session/consent/freshness/tool-budget summary, truthful empty user-history
and action states, and filters distinguishing expired preview, confirmed unrouted
request, routed waiting request, real clinician decision, nonclinical execution and
withdrawal. An unrouted confirmed proposal is not displayed as waiting for an
informed clinician. Consent checkboxes reset before each explicit new-session
submission; unresolved payload/key remains in the existing controller. UI filters
never submit/confirm. No generated replies or medical action inferred.

Files: agent/agent_workspace_summary.dart, server_agent_models.dart,
server_agent_ui.dart, test/wave_agent_experience_test.dart.6 new tests, focused41,
full1891, analyze clean. Existing withdrawal/expiry/stale/late/logout/duplicate
controller tests retained. Real320px/200% light/dark consent and filter tests.

M1 remote verifiedd3e7f5f07c0d5433b9ec4988f58def1b68cce0cf.

## M2 inbox/reminder UX — DONE bounded

Loaded-only category/unread filtering and due-UTC day headings preserve server
order and paging, make filtered-empty state explicit, and distinguish loaded counts
from global unread totals. Existing safe notification navigation remains unchanged:
a message notice opens authorized conversations, not an inferred thread ID.
Settings confirmation resets when timezone/quiet times/category/reminder/fold draft
changes, preserving original server CAS and DST scheduling contract. No local
scheduler or device token registration. No optimistic read or delivery claim.

Files: notifications/inbox_models.dart, inbox_ui.dart,
test/wave_notification_experience_test.dart.7 new tests, focused30, full1898,
analyzer clean; existing current401/403/late/logout/withdrawal/CAS tests retained.

## M3 evaluation history — DONE bounded

Actual ordered GET /clinical-plans/{id}/history integrated into the dedicated
withdrawal metadata transport. Strict minimal projection rejects malformed,
foreign-plan, unordered and nonprogressing pages without retaining clinical
payloads. Explicit original-job history recovery scans one page per user action
and waits for complete history before resolving a cancelled original job; a newer
current job remains separate and is never cancelled by that recovery.
Historical metadata is not current authorization or inference evidence.

Files: services/api_service.dart, consent/evaluation_withdrawal.dart,
plans/plan_ui.dart, test/wave_evaluation_history_test.dart.20 new tests,
focused41, full1918, analyzer clean. Covers pagination, malformed histories,
401/403/404/409/410/422/503 and late session/visibility races; synthetic HTTP only.

## M4 messaging prepend — DONE bounded

Added AnchoredConversation with lazy slivers growing above a stable original
server sequence. Variable-height earlier rows and later appended messages retain
the visible original row without estimating total height. UTC presentation and
server ordering retained. Origin day header is repeated as a continuation boundary
to preserve its geometry. Widgets remain generation/thread keyed, disposed on
private-view loss; no new private cache or delivery claim. Existing controller
frozen pagination, overlap rejection, watermark and consent tests retained.

Files: messaging/anchored_conversation.dart, messaging_ui.dart,
test/wave_message_anchor_test.dart.4 new actual-widget tests with 100 variable
height rows, 320px/100%/200%/both themes, append and reverse scrolling. Focused35,
full1922, analyzer clean. No mobile runtime claim.

## M5 private views versus unresolved identity — DONE bounded / PARTIAL domain audit

Current401 and credential expiry now quarantine minimum PendingIntent metadata
before clearing all private payloads/views. Authentication attempts retain that
account/role-scoped memory quarantine; another account cannot read it. Explicit
logout/init/account deletion still erase it. Same-path replacement mutations are
blocked before HTTP; blocked unsent replacements are not new uncertain operations.
No original body, token, invitation or clinical text crosses that boundary.
Original grant/job/revisions are projected for implemented typed plan/evaluation,
message, product and configuration operations. Notification expected_revision0 is
supported because that is the real initial settings CAS.403/503 protected reads
retain current-session pending identities while wiping visible content.

This is memory quarantine, NOT process-death recovery or restored authorization.
Special legacy doctor write sets are still session-bound and outside this typed
PendingIntent quarantine; full domain durable recovery remains PARTIAL. Agent and
invitation receipt routes do not acquire cross-login validity from retained metadata.

Files: integration/operation_identity.dart, contract.dart, configuration_receipt.dart,
services/api_service.dart, products/product_operation.dart,
messaging/messaging_controller.dart, plans/plan_controller.dart,
consent/plan_withdrawal.dart, evaluation_withdrawal.dart,
test/wave_operation_quarantine_test.dart.7 new tests; focused30 with notification
regressions, full1929; analyzer clean. Read401/403/503 tested for both roles,
replacement suppression, same/wrong account, explicit logout and metadata rejection.
