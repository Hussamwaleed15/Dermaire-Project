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
