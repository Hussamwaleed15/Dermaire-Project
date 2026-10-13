# M3-F3 — Patient contextual chat

Source a932a209d248fab262d9a467546f9c46ebe7e1b0 (verified F2 commit/push).
Actual POST /chat uses the same AssistanceRequest (message <=1000; optional task)
and read-like assist service. No conversation ID/history/streaming/action API.
ChatMessageResponse contains reply/kind/escalation_triggered/azure_model_used and
nullable safety_details. Current serialization includes authoritative_safety plus
contextual_assistance. PatientChatReply validates wrapper separately, canonical text
and safety consistency before using the embedded F2 DTO. Unknown/incomplete wrappers
are unsupported, not a fake reply. No history/profile/images added to request.

PatientChatController binds generation/owner/confirmed patient consent and maintains
up to20 in-memory question/response turns. No generated conversation IDs or storage.
Local submitted/received UTC timestamps explicitly describe device events, not server
persistence. Clear/drop/dispose/logout/switch/revocation invalidates pending requests;
old401/reused-token cannot expire B. Duplicate sends blocked, empty/oversized messages
rejected, unsent composer stays responsive. Failed/timeout/unsupported replies are
error states with no synthetic assistant answer. One manual retry per failed turn;
read-like retry can repeat provider invocation. No automatic resend or write action.

SkinAssistantScreen uses existing shell entry and shared F2 evidence renderer.
Safety snapshots are always visible; evidence/provider/uncertainty details expand,
without duplicate reply text. Separately fetched ClinicalHomePanel remains above
turns. Source kind and compatibility label are not interpreted as a doctor or actual
AI-provider invocation. No local medical fallback/triage is used by this screen.
Legacy unused SkinAssistantSafety exports and legacy Tester API methods retained to
preserve existing regression/Tester interfaces; they are not called by patient chat.

Explicit temporary-view/no-memory disclosure, selectable whole responses, no fake
streaming/thinking, keyboard send, long scroll/select, send/clear controls, conditional
follow-end scroll, reduced motion, Light/Dark and320px/200% text. No dead Contact Doctor
button, medical writes, implicit action execution, provider changes or local logs.
Server prose remains verbatim (including the known legacy bilingual precaution).

Verification: analyzer clean; full suite **973 passed =949 preserved +24 new**.
Synthetic account/HTTP fixtures only, production denial retained. Typed/unknown envelope,
evidence/safety consistency, validation, duplicate/limited retry, error/current/old401,
clear/dispose/switch/logout/revoke, bound/no-history payload, long text/keyboard,
Light/Dark/reduced/large/composer and no local fallback tested. Two prior chat widget
fixtures were genuinely obsolete (unauthenticated + incomplete wrapper); updated to
actual server consent and complete envelope while preserving both server-only text
and failed-server/no-local-conclusion assertions. No valid test removed/weakened.
Device/emulator QA not performed. F3 supported stateless chat complete; durable memory,
streaming, agent tools, proactive monitoring and future image model remain unavailable.
