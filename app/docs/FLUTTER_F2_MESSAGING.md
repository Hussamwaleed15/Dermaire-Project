# F2a — consented care messaging integration

Source before increment901a512509ac44af422951e1c013392f43811756. Verified current
backend messaging router/schema/service and MESSAGING_CONTRACT; no backend edits.
New app/lib/messaging typed models/controllers/UI use real /messaging/threads,
messages, attempts, read and consent routes through the guarded existing client.
Patient Profile and Doctor Workspace now link to Care conversations.

Patient enrolls by selecting an actual currently active VIEW grant and explicitly
checking messaging consent. Server confirms the original grant/thread. No new grant
can reopen an old thread; closed/foreign/expired/revoked responses clear private
content. Doctor and patient read actual ordered messages and app-read watermarks;
app read is not push delivery or medical clearance. Participant content stays text.
Latest50 messages and frozen-high earlier pages merge by immutable identity;
500-message display bound and manual current refresh. No socket/push update promise.

A send stores one memory-only exact body/key per original thread/session. POST201
receipt ID/actor/thread/content must validate, then current message high watermark
is read. Lost reply/5xx/malformed/readback denial stays unresolved. GET attempt
reconciles committed result; unknown permits only explicit same-key/body retry,
never automatic or replacement-key replay. Receipt identity and current state are
separate. An expired receipt stays locked for history review. Duplicates and stale
callbacks cannot publish old-account content. Logout clears pending bodies/keys.
Original uncertainty survives editor recreation within the authenticated session.

Shared integration/private_view reuses current architecture (ChangeNotifier,
ApiService/guarded session transport and existing lifecycle mixin). Background/cover/
logout/session change clear records/drafts/cursors. Permission withdrawal remains
reachable without displaying content after policy acceptance is lost.

25 new isolated tests: patient/doctor send/read; explicit enrollment; frozen paging;
current/old401,403/409/410/422/503, before/after-commit loss, malformed actor/thread,
denied readback remains uncertain, original-body/key retry, duplicate/hide/logout/
account switch, withdrawal/replacement authority and320px/200% light/dark/reduced
motion widgets. Final pub get success, analyzer **No issues found**, full suite
**1373 passed** (1348 preserved +25). No Production/OAuth/device/native execution.

Remaining F2: typed clinician follow-up plans and scheduling. F6 integration polish
includes patient-context message links, day grouping/scroll UX and broader lifecycle
flows. No genuine push delivery, medical/emergency response or clinical certification.
