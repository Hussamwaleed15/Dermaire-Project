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
| Doctor grant management/entry | PARTIAL | doctor/access_invitation.dart actual intended-doctor VIEW issue/key attempts/current scoped claim; doctor_models.dart optional real scope readback; patient entry bulk withdrawal now uses actual keyed original receipts without accepting policy; selective entry withdrawal with original receipt/current grant verification integrated; restart recovery remains |
| Persistent messaging | PARTIAL | messaging/messaging_models.dart, messaging_controller.dart, messaging_ui.dart; real enrollment/list/send/read/paging/withdraw/reconciliation integrated; UTC day grouping integrated; context and prepend-scroll polish remain |
| Typed clinical follow-ups | PARTIAL | plans/ models, controllers, UI; actual create/ack/cancel/reschedule/review/history/reconciliation; patient policy-loss cancellation integrated; broader comparison UX/runtime remain |
| Inbox/preferences/reminders | PARTIAL | notifications/inbox_models.dart, inbox_controller.dart, inbox_ui.dart; real inbox/read/history/CAS preferences/routine reminders/withdrawal; Agent deep links and device provider remain unavailable |
| Plan-linked comparison | PARTIAL | plans/* typed original-grant plan/source/baseline, private images, guided capture association, evaluation consent/status/review/attempts; model unavailable; patient plan/evaluation policy-loss withdrawal integrated; restart/history recovery remain |
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

L2a remote verifieddc24dfc4ebb50aafcd88e828930252c7d41d9bc8. F6-L3a denied Safety/clinical review/PSM safety/Home/observation cache correction: full1854 (+10), focused77, analyzer clean. Existing scope/session tests retained; L3 full cross-domain journey review remains PARTIAL.

L3a remote verified242f8d2b9ef52ffb60ef689f845ec0101587f263. L2b evaluation withdrawal: full1875 (+21), focused65, analyzer clean. Safety metadata manager now separates original job cancellation from parent participation withdrawal; latest-job replacement cannot resolve an original handle. Historical evaluation recovery remains PARTIAL L5.

L2b remote verified4ba7c12c6398d3ef771b810147b597d0fd044919. L9a: full1879 (+4), focused4 shared multi-domain workflows, analyzer/pub get clean. SDK integration_test device entry prepared and statically analyzed; no device execution or process-death proof claimed. L9 overall PARTIAL; L10 runtime BLOCKED by actual device/SDK inventory.

L9a remote verified3041fb6e90810c78402d977064220109d278d96d.
L8a messaging UTC day grouping/readable timestamps/accessible semantics: full1885 (+6), focused31, analyzer clean. Server order/read-watermark and lazy rows preserved. Broad notification/Agent UX and all-feature patient/doctor journeys remain PARTIAL; no model/push/device/restart completion claimed.

F6-M start a93ab02097af15027e9b1b0ab3913f10b14b6b89, baseline1885. M1 Agent workspace/consent/action-stage UX: full1891 (+6), focused41, analyzer/pub get clean. Discovery/pagination/model remain source-verified boundaries; see FLUTTER_F6_M_EXECUTION.md.

M1 remote verifiedd3e7f5f07c0d5433b9ec4988f58def1b68cce0cf. M2 loaded inbox filters/day grouping and draft-bound settings consent: full1898 (+7), focused30, analyzer clean. Current server scheduling/read/withdrawal behavior preserved; real push unavailable.

F6-M M3: bounded historical evaluation read/recovery implemented; focused41, full1918, analyzer clean. Original and latest jobs remain separate. See FLUTTER_F6_M_EXECUTION.md.

F6-M M4 bounded prepend anchoring: focused35, full1922, analyzer clean. Lazy centered slivers preserve visible row geometry; actual small-screen large-text widgets tested.

F6-M M5 PARTIAL overall; minimum operation identity quarantine separated from private view/payload cleanup. Current401/expiry preserve scoped metadata; no automatic replay.7 new tests, focused30, full1929, analyzer clean. Legacy doctor write sets and durable recovery remain separate work.

F6-M M6 PARTIAL: versioned metadata journal protocol/coordinator/cleanup and real product receipt review implemented;31 new tests, focused58, full1960, analyzer clean. Native SQLCipher adapter BLOCKED specific approval + device qualification. Review exact unapplied docs/proposals/secure_journal_native_review.patch; no native or dependency edits applied.

F6-M M7 bounded connected-care journeys and legacy doctor/grant identity lifecycle DONE; whole-device/full-roadmap integration PARTIAL.15 new tests, focused98, full1975, analyzer clean. Legacy PendingIntent quarantine gap noted in M5/M6 is now addressed for actual notes/reviews/grant withdrawal; no new server idempotency semantics claimed.
