# Product M5 implementation checkpoint —14 November2026

Verified main b995873f2b76e0c37a08f23fbf40322174aba6fe; PR6–13 current metadata inspected. Base PR7 5d855b499f73866ba6894fe67f950e81ec1b6e51 is the earliest sufficient source containing F8 notification state_revision CAS and trusted thread target. PR6 ancestry retained. PR8 adds independent Agent ordering/tests/workflow, not required notification source; test compatibility with it separately. No unrelated M1–M4 stack imported.

Canonical complete Master Plan v1 previously read in this conversation, unchanged PR10 provenance reverified (blob dd7d3689579095c79f986f723f3f941b5788ede4); retrieved exact document into temporary read-only context. app/AGENTS.md applies. Six requirements: inbox/preferences; reminder consent/scheduling; device registration with permission; real push proof; secure cache/drafts; original reconciliation/session cleanup.

Existing: PrivateView route/lifecycle cleanup and GET resume; CAS settings with exact normalized PendingIntent; F8 app-read CAS/navigation; real domain receipt readers; isolated SQLCipher session NOT composed into production; current API clears private payloads and quarantines only minimum identities on expiry. No duplicate recovery subsystem.

Five demonstrated safely code-addressable workstreams:
1. Enforce actual inbox created_at DESC,id DESC ordering/page bounds and bounded cycle-free continuation without inventing history timestamps or requiring privacy-filtered cursor to be visible.
2. Validate transport/attempt metadata; never render unsupported delivered claims or confuse provider acceptance with delivery.
3. Preserve settings original unknown identity when current CAS state advances; current desired values are not an original operation receipt. Validate unchanged-revision settings consistency. Successful synchronous original acknowledgments remain separate from later current readback.
4. Preserve original uncertain app-read CAS identity through refresh/hide; no replacement at the same unfenced revision, no automatic replay. Later revision may fence old request but must not fabricate its original outcome.
5. Show server read freshness, session-memory-only draft/intent lifetime and independent permission/token/registration/provider availability. No private persistence, permission prompt/token acquisition or native SDK added.

Tests: actual controllers/HTTP, two nonempty pages/ties/out-of-order/bounds/cycles/private-filtered empty page, settings lost response/current changed/receipt vs current, read CAS timeout/newer revision/session/hide/disposal, honest transport states, both themes320px200%reduced motion. Full related/full/analyze, exact disposable M1–M4/F8 combinations, correct stacked Draft PR. No journal/provider/workflow/worker activation, Backend/native/Tester edits, merge, QA closure or M6 start.

Reconciliation follow-up: sixth demonstrated gap — lower-priority history read failure erased an independently valid inbox. Separate partial transport-history failure/retry, but401/403 still wipe all protected view state. No cached history is presented as current.
