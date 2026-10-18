# Flutter integration wave — implementation status

Audited remote source8ad2ceafced5b1f06ade5a082d4939503d31c687;2026-10-18.
This is a live execution ledger, not a claim of overall completion.

| Area | Status | Actual Flutter paths and remaining work |
|---|---|---|
| Auth/current safety/profile review | DONE bounded current contract | services/api_service.dart, entry/server_entry_metadata.dart, onboarding_screens.dart; legacy metadata absence compatible; no future policy text invented |
| Entry identity/light-dark logos | DONE preserved | dermaire_logo.dart, entry/*; supplied assets unchanged |
| Patient Home/atomic snapshots | PARTIAL | home_controller.dart, clinical/*; new snapshot/freshness integration pending |
| Profile/observations/private capture | PARTIAL | account/*, observations/*, capture/*; new association/receipts pending |
| Products/routines/adherence/experiments | PARTIAL | products/*, routine/*, experiments/*; new CAS and operation receipts/history pending |
| Deterministic PSM | PARTIAL | psm/*; latest schema/freshness compatibility pending; not image AI |
| Doctor grant management/entry | PARTIAL | doctor/*, doctor_portal.dart; explicit new grant issue/claim replacing legacy block pending |
| Persistent messaging | PARTIAL | messaging/messaging_models.dart, messaging_controller.dart, messaging_ui.dart; real enrollment/list/send/read/paging/withdraw/reconciliation integrated; context/day-group/scroll polish in F6 |
| Typed clinical follow-ups | NOT STARTED | /clinical-plans exists; old text guidance preserved |
| Inbox/preferences/reminders | NOT STARTED | notifications/notification_availability.dart remains old availability page until new source adapter is verified |
| Plan-linked comparison | NOT STARTED | comparison/* retains isolated unsupported scaffolding, no fake plans |
| Agent sessions/actions/requests | NOT STARTED | agent/* old scaffold; persistent broker not integrated yet |
| Genuine model inference | BLOCKED | Provider/model unavailable in actual backend; no synthetic assistant responses |
| Push delivery | BLOCKED | No real configured mobile token/provider transport/device proof; inbox independent |
| Cross-domain privacy/recovery | PARTIAL | existing generation/current401/disposal guards retained; extend and test every new domain |

F1: baseline1335; full suite1348 (+13), analyzer clean after lint repair,
focused13 rechecked immutable payload handling. No backend/native/Tester changes.
F2–F6 continue; statuses updated after verified implementation, not on planning.

F2a messaging: full1373 (+25), analyzer clean, original-key/receipt and policy-withdrawal regressions pass. F2 follow-up plans continues next.
