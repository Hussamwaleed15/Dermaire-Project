# M5-F5 — integrated recovery UX (PARTIAL overall; supported UX COMPLETED)

Starting main/origin/main: e11f4c6e1a9487e1c1ce063c76405175b24b4caa.
Reusable RecoveryNotice is integrated into existing routine, experiments and
product library. It displays actual failed request feedback, same-session prior
confirmation/staleness and last confirmed *read* time (not clinical clearance),
and an explicit preserved uncertainty warning. Refresh calls only existing guarded
GET paths. Concurrent/loading/saving/history controls are disabled appropriately.
No feed/navigation badge/notification history, dead bell, schedule switches,
clock reminder editor or automatic network observer was added. Profile's existing
availability explanation and routine timing disclosure are preserved.

Previously confirmed routine/product rows remain readable during refresh with
stale labels; mutation controls remain guarded. Experiments retain their own
observed associations/saved evaluation distinctions. Clinical panels remain above
recovery feedback and do not turn unavailable safety into medical clearance.
Home projection/completion, guided camera, comparison timing, PSM, stateless chat,
Agent execution/memory and clinician authority are not rewritten.

Reduced-motion loading uses static waiting text; default loading retains semantic
progress. Existing brand/theme tokens, scroll layouts, readable text, native Back
and accessible labeled controls are used. No success animation is tied to a retry.
Product creation rejected before dispatch (stale/loading) no longer invents an
uncertain server creation; actual dispatched failures remain uncertain.

Notifications/preferences/feed/reminders/follow-up delivery remain BLOCKED by
missing contracts and a complete safe scheduling mechanism. F5 is not a full
operational notification experience. No OS permission state is guessed; no
permission calls occur. Real denied/allowed delivery testing remains external.

19 new tests: eight responsive/contrast/semantic/reduced-motion recovery widgets;
two creation-before-dispatch guards; four real mocked routine offline→GET recovery
→uncertain adherence→GET/no replay→logout journeys; two experiment retry/disabled
mutation/reduced-motion journeys; two product recovery/no fake creation journeys;
one availability/Back journey. All 19 focused tests passed; full **1164 tests passed** (1145 + 19 new).
Final flutter analyze: **No issues found**. Existing failure/retained-row widget
now scrolls to data below the accessible recovery card; assertions preserved.
F3/handoff clarified existing free-text ClinicalNote.follow_up versus absent
typed schedule/receipt. No clinical-note parsing or Doctor Portal code changed.
No simulator/emulator/device/native build, production HTTP/OAuth/push or backend,
Azure, DB, provider, Tester, Doctor Portal or unrelated native changes.
