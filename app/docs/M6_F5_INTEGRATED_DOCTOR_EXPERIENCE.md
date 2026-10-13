# M6-F5 — integrated doctor experience (PARTIAL)

Source before phase: 6fdf04834d37ffd100611cab004c75d09947df88.
Supported integration COMPLETE; genuine doctor-patient messaging BLOCKED.
Inspected backend router/model/schema/service sources: doctor success messages
are acknowledgements, not care messages; /chat and contextual_ai are patient AI
education, not authorized clinician conversations. No conversation participants,
message creation/list/durable history/pagination/read receipts/attachments/retention/
consent/notification contracts. No unrelated endpoint is used to send care messages.
Existing Flutter doctor chat dead controls/false success have been removed in F1.
The integrated UI truthfully describes messaging as unavailable. No fake local inbox.

One real journey: provisioned role -> password or existing-role mocked Google ->
server safety acceptance/profile -> authorized connection list -> fresh patient grant
-> independent canonical Safety/current and historical reviews -> bounded source
records/on-demand private image -> immutable note/review -> confirmed GET readback.
Patient-visible notes/guidance read through the real patient review projection.
No role elevation from registration/local AccessSession or constructor patient IDs;
no license badge, export, autonomous Agent write, appointment or reminder.

Added shared route/background lifecycle. Covered record/edit pages clear records,
pixels and in-memory drafts; background clears workspace lists and patient access.
Inactive/hidden/paused/detached all close sensitive scope. Resume/Back requires fresh
profile/list when needed and fresh exact-patient grant, then resource reads. Delayed
resume checks are view/session-bound; no writes are replayed. Back from patient B
reactivates A only through a fresh grant read. Image reopening is explicit; no auto
restore of pixels. Medical data is not persisted in local preferences/disk/logs.
No continuous grant-revocation feed claim: each server request reauthorizes, expiry
clears data; no promise of instant server-push changes between reads.

Fixed a real Navigator-frame sibling notification issue discovered by the integrated
entry tests. Selection identity changes synchronously; UI notifications during a
Navigator mount are scheduled safely for the end of that frame. Late scopes already
fail identity guards. Clinical choices use responsive labeled ChoiceChips within the
page so selecting priority/status does not open another route or erase its draft.
Connection list priority/check-in context is explicitly a retrieved snapshot;
current Safety and clinical detail are read separately.

27 new isolated tests: aggregate decoded-image budget across scopes; inactive/hidden/
paused/detached lifecycle; full mocked password/Google acceptance and no patient API
requests for doctors; grant/detail -> real note readback; covered/background/late
writes/no replay/no stale success; decoded image close on cover/background/logout/
account switch; Back/revoked/session recovery; 320px/200% light/dark/reduced motion,
labeled tap targets and authorized draft-preserving choices, same-widget account/patient rebinding and
explicit connection-disposal pixel cleanup. Clinical text cleanup also guards
deactivated elements during unmount; reactivation clears invalid drafts before
showing the editor. Full earlier suites
remain required. No real OAuth, Production traffic or device/platform execution.

Final gate: flutter analyze **No issues found**; full flutter test **1335 passed**
(1308 preserved +27 new). All M1–M5/M6-F1–F4 regressions preserved. New scope-disposal
and same-widget rebind regressions pass. One final lint-only braces repair does not
change the behavior verified by that full run; analyzer rerun is clean.
