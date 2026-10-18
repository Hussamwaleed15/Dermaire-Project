# Flutter integration wave — implementation status

Audited remote source8ad2ceafced5b1f06ade5a082d4939503d31c687;2026-10-18.
This is a live execution ledger, not a claim of overall completion.

| Area | Status | Actual Flutter paths and remaining work |
|---|---|---|
| Auth/current safety/profile review | DONE bounded current contract | services/api_service.dart, entry/server_entry_metadata.dart, onboarding_screens.dart; legacy metadata absence compatible; no future policy text invented |
| Entry identity/light-dark logos | DONE preserved | dermaire_logo.dart, entry/*; supplied assets unchanged |
| Patient Home/atomic snapshots | PARTIAL | clinical/clinical_snapshot*.dart actual patient/doctor shared-clock transaction bundle linked from Home/Reports and patient context; independent controllers remain separate reads |
| Profile/observations/private capture | PARTIAL | account/*, observations/*, capture/*; new association/receipts pending |
| Products/routines/adherence/experiments | PARTIAL | products/* actual editor retains server identity and original quoted PATCH/DELETE revisions; routine/* and experiments/* consume original revisions; explicit reviewed dual-resource activation supports safe routine opt-in; product_operation.dart / product_repository.dart / products_controller.dart / products_ui.dart now integrate create/patch/delete original receipts and explicit check/retry/review; routine/routine_controller.dart + integration/configuration_receipt.dart now integrate create/edit/PATCH-stop receipts and actual UI recovery; experiments/experiment_controller.dart + experiment_ui.dart now integrate create/edit/activate/finish/cancel/evaluate receipts and exact dual-header recovery; routine/adherence_operation.dart + routine controller/UI now integrate keyed immutable report receipts and current-history recovery; signed full-history/calendar integration and restart recovery remain |
| Deterministic PSM | PARTIAL | psm/*; latest schema/freshness compatibility pending; not image AI |
| Doctor grant management/entry | PARTIAL | doctor/access_invitation.dart actual intended-doctor VIEW issue/key attempts/current scoped claim; doctor_models.dart optional real scope readback; patient entry bulk withdrawal now uses actual keyed original receipts without accepting policy; selected revoke/restart recovery remain |
| Persistent messaging | PARTIAL | messaging/messaging_models.dart, messaging_controller.dart, messaging_ui.dart; real enrollment/list/send/read/paging/withdraw/reconciliation integrated; context/day-group/scroll polish in F6 |
| Typed clinical follow-ups | PARTIAL | plans/ models, controllers, UI; actual create/ack/cancel/reschedule/review/history/reconciliation; comparison-specific UX and policy-withdrawal extension pending |
| Inbox/preferences/reminders | PARTIAL | notifications/inbox_models.dart, inbox_controller.dart, inbox_ui.dart; real inbox/read/history/CAS preferences/routine reminders/withdrawal; Agent deep links and device provider remain unavailable |
| Plan-linked comparison | PARTIAL | plans/* typed original-grant plan/source/baseline, private images, guided capture association, evaluation consent/status/review/attempts; model unavailable; policy-loss withdrawal/restart recovery remain F6 |
| Agent sessions/actions/requests | PARTIAL | agent/server_agent_* actual consent/session/context/user-turns/preview/confirm/routing/doctor decisions/revocation; unsupported model/session discovery remain explicit |
| Genuine model inference | BLOCKED | Provider/model unavailable in actual backend; no synthetic assistant responses |
| Push delivery | BLOCKED | No real configured mobile token/provider transport/device proof; inbox independent |
| Cross-domain privacy/recovery | PARTIAL | existing generation/current401/disposal guards retained; extend and test every new domain |

F1: baseline1335; full suite1348 (+13), analyzer clean after lint repair,
focused13 rechecked immutable payload handling. No backend/native/Tester changes.
F2–F6 continue; statuses updated after verified implementation, not on planning.

F2a messaging: full1373 (+25), analyzer clean, original-key/receipt and policy-withdrawal regressions pass. F2 follow-up plans continues next.

F2b follow-ups: full1395 (+22), analyzer clean. See FLUTTER_F2_FOLLOW_UPS.md.

F3 inbox/settings/reminders: full1418 (+23), analyzer clean; pub get succeeded.
F2b remote verified60e6bae6c75e1d70035991ca5ac4d0b51de998bb.

F4 comparison: full1440 (+22), analyzer clean; pub get succeeded.
F3 remote verified756c89c8dab47f4317ad8f920d9ed5d7e67013a9.

F5 server Agent broker: full1475 (+35), analyzer clean; pub get succeeded.
F4 remote verifiedaaf8d56d60e9363775c53677abfe955559bfd838.

F6a clinician linking: full1507 (+32), analyzer clean; pub get succeeded.
F5 remote verified3377f683c862d1698d6af8dc2078b4831048810a.

F6b clinical snapshots: full1538 (+31), analyzer clean; pub get succeeded. F6a remote verified5eee1d888a0c08cf0cf708c0b5c6e7bfb845e43a.

F6c-1 products: full1566 (+28), analyzer clean; pub get succeeded. F6b remote verified5006c796829a9c3d0bc88bed049ff3818c9622f7.

F6c-2 protected routine edit/stop: full1590 (+24), analyzer clean; pub get succeeded. F6c-1 remote verifieddc73dbc970ea126ac396be638adc1fc9638d7d79.

F6c-3 experiments/linked routine: full1625 (+35), analyzer clean; pub get succeeded. F6c-2 remote verified45c19219352e85ee18c042acf9f1ecfb76a1edc9.

F6 continuation start3efe4b5a36e793e12628d8d3d4f8aafe6a75d3e5; fetched identical main; baseline1625. F6d-1 product receipts: all1652 (+27), analyzer clean. Controller recreation is session memory only; F6e persistence not yet implemented.

F6d-2 routine configuration: all1681 (+29), analyzer clean, pub get succeeded. F6d-1 remote verified04e6e9114fbf4778d5c89979611ffbfccc8bfae5. F6e durable exact-request recovery BLOCKED: no suitable configured durable/protected journal; current shared_preferences explicitly lacks disk durability guarantee and is unsuitable for critical operation identity/payloads. Android/iOS runtime validation BLOCKED: fresh device inventory macOS only and no emulator sources.

F6d-3 experiments: all1713 (+32), analyzer clean, pub get succeeded. F6d-2 remote verifiedcdfc8da32c5dd4b81c913552e1f7cc98fdbb4c81. Agent/notification/provider gaps reverified in actual source; platform restart and device blockers remain explicit.

F6d-4 adherence: all1741 (+28), analyzer clean, pub get succeeded. F6d-3 remote verified3285a1b9839f61c450c597ce7e00fde2c5fddac2. Unresolved refresh remains locked; actual externally resolved operations unlock only on a fresh successful read.

F6g-1 recovery projections: all1762 (+21), analyzer clean, pub get succeeded. F6d-4 remote verified0931bef57bcde05136b2ec975acb30a0b020fa21. Product/routine/adherence/experiment recovered writes request actual related Home/clinical reads with callback busy/session guards; failed projections remain unavailable. Broader privacy/withdrawal/navigation work remains PARTIAL.

F6g-2 entry withdrawal: all1790 (+28), analyzer clean, pub get succeeded. F6g-1 remote verifiedd409d6917d820c0ad9791116c3025aa1151bf7bb. Actual Safety entry links to patient bulk clinician withdrawal without policy acceptance or private record reads. Original receipt does not claim current permissions; selected withdrawal/plan policy-loss work remains PARTIAL. See FLUTTER_F6G_ENTRY_WITHDRAWAL.md.

F6g-2 remote verified238b5edcfcd199207900c6f361d16dabf32b310d.
F6h-1 implemented denied/session read-cache removal for products/routines/experiments, including paged histories, while preserving unresolved mutation identities. Broader F6h remains PARTIAL. See FLUTTER_F6H_FOUNDATION_READ_PRIVACY.md for exact files and tests.

F6h-1 verified: full1808 (+18; continuation total+183), focused49, analyzer clean, pub get succeeded; diff check clean. The older403 routine assertion was corrected to require record removal plus fresh authorized recovery. No code or native dependency change outsideapp/.

F6-L1 selective withdrawal: full1828 (+20), focused48, analyze/pub get clean. Safety entry now supports explicit original grant selection without current policy acceptance, owned metadata only, keyed original receipt plus independent current grant verification. Restart persistence remains BLOCKED; other L milestones continue.

F6-L2a: full1844 (+16), focused44, analyzer clean. Safety entry → metadata-only plan participation withdrawal, original grant/plan/CAS/key + historical receipt/current readback. Evaluation cancellation after policy loss remains PARTIAL. Secure recovery assessment documented in FLUTTER_SECURE_RECOVERY_DECISION.md; implementation/device proof BLOCKED.
