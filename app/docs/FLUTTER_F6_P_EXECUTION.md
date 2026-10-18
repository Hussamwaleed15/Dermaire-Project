# F6-P source-grounded backlog and execution
Start2026-10-19,745b26ee5224632fe121ccde31d6bd6091d757c7; clean main, official origin
fetch/push verified and fetch matched. Fresh pub get/analyze clean,2021 tests pass.
No native/backend/Tester changes or real calls authorized. Journal remains disabled.

| Feature/source/tests | Actual API / current status | Missing behavior / priority |
|---|---|---|
| Auth/entry/account: onboarding_screens,entry,account; entry/safety/profile tests | /auth + /users/me + completion receipts; DONE bounded contract | Preserve current safety/profile gates and role/session semantics |
| Home: home/patient_home,home_controller; home tests | /home,/baseline,/safety,/checkins; PARTIAL product integration | P1 direct care navigation and visible reliable actions; no fake report-only metric completion |
| Observations/capture: observations,capture; observation/guided/history tests | /checkins,/captures; DONE bounded software / PARTIAL device | P1 restore centered bottom action; keep separate observation/capture provenance |
| Products/routines/experiments: products,routine,experiments; receipt/CAS tests | real keyed mutations and original receipts; PARTIAL integration | Preserve existing related refresh; P1 add actual prospective configuration history |
| Timeline: ObservationHistoryScreen and doctor evidence | /checkins + separate histories; PARTIAL | P1 connect recorded routine history; label cutoff/provenance/unknown legacy evidence |
| Calendar | /routine/calendar-policy exists, no mobile consumer; NOT STARTED | P1 explicit prospective timezone/CAS UI without relabeling UTC adherence or reminders |
| PSM: psm; evidence tests | /psm versioned evidence; PARTIAL | Preserve unavailable model, improve reachable evidence context if source supports |
| Grants: doctor/patient_access,access_invitation; withdrawal tests | actual VIEW/EXPORT and keyed grants; DONE bounded / PARTIAL restart | P3 current grant loss + uncertain identity preservation; no false export support |
| Messaging: messaging; stable-scroll/consent/workflow tests | /messaging enrollment/threads/receipts; PARTIAL connectivity | P2 patient-filtered doctor conversation entry, preserve grant/consent rechecks |
| Plans/comparison: plans,comparison; plan/history/withdrawal tests | /clinical-plans + evaluation/history; PARTIAL | P2 contextual patient plans and refresh after navigation; real model BLOCKED |
| Doctor: doctor_portal,doctor/*; doctor/current/private tests | /doctor/patients + current grant; PARTIAL | P2 current patient contextual messaging, truthful scope feedback, patient-switch tests |
| Notifications: notifications; inbox/reminder tests | /notifications + preferences/reminders/history; PARTIAL | Preserve loaded-only filters; safe targets, no invented thread; delivery BLOCKED |
| Agent: agent/server_agent*; lifecycle tests | real broker/session/action/requests; PARTIAL | current request lifecycle and consent; discovery/pagination/model remain verified contract gaps |
| Account UX: app_shell; entry/privacy tests | no export endpoint; PARTIAL | P1 remove fake export/accessibility success, truthful methodology and real navigation |
| Cross-domain privacy: integration/private_view,controllers,images | current session/original grants; PARTIAL | P3 verify late/denied responses and forms/navigation, preserve only uncertainty identity |
| Secure recovery: recovery + N tests | SQLCipher + product reader isolated; PARTIAL | P4 add real configuration/adherence/clinical readers where source permits, never production activation |
| Connected workflows | existing8 care +4 withdrawal + separate foundation tests; PARTIAL | P6 extend real widget journeys across foundation/care and context switching; no fake E2E claims |

Planned verified increments: patient navigation/trust/accessibility; prospective routine
history/calendar; contextual doctor journey; cross-domain privacy; extra software-only
journal readers; consolidated workflow/UX checks and reverified Hussam handoff. Adjust
from actual failures/source evidence without dropping blocked domains. Every meaningful
increment requires focused/full tests, analyze, diff, normal commit/push/remote check.

P1a DONE bounded navigation/trust increment: central camera action restored without
changing six existing state indices/destinations; semantic tappable labels/tooltips,
icon-only small/large-text navigation and reduced motion. Home connected-care entry
returns through actual server projection refresh and captured-session guards. Account
export/accessibility placeholders replaced by honest data-review and real preference
readback/appearance controls; methodology no longer claims on-device extraction or
available AI. Existing Home test now ensures actual button visibility before tap;
all result assertions retained.10 new regressions, focused81, full2031, analyze clean.
No native/backend/Tester or journal activation changes.

P1b DONE bounded prospective routine evidence/calendar: actual signed-cursor history
and owner/filter/order/provenance validation; current calendar readback + explicitly
approved forward-only IANA-zone change under original CAS. No UTC adherence rewrite
or reminder change. Lost response retains frozen original draft; same-revision
unknown locks replacement, explicit exact original retry only. A fresh higher
calendar revision fences old CAS under the verified account lock; this is NOT an
original receipt. Account-expiry quarantine still has no calendar receipt reader.
Links from Routine, Reports and observation timeline;320px/200% consent resets on
draft change.24 new tests, focused64, full2055, analyzer clean. No native changes.
