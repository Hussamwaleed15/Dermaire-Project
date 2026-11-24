# M2 implementation checkpoint — 14 November 2026

Base: main b995873f2b76e0c37a08f23fbf40322174aba6fe. Capture, private images and clinical plans already exist here. PR6–8 authority and PR9–10 Home changes are independent; do not copy or activate them.

Verified contracts: GET /captures?limit=100 (owner metadata, receipt ordering, no cursor), GET /captures/{id}, GET /measurements/{capture_id} (existing measurements only, 404 is not a zero), authenticated image GET. measurement-1.0 returns two nonclinical fraction proxies, capture-quality-1.0, timestamps, provenance, reason, region, reliability and optional comparison metadata. No new writes or measurement generation.

Code-addressable gaps:
1. Bounded chronological measurement history, batches of five from the latest 100 capture receipts, explicit further reads and per-record retry/error/absence; no trend/delta or clinical inference.
2. Shared complete measurement evidence presentation for immediate results, details and history, including unsupported/absent comparison and malformed embedded estimates.
3. Rebind history/detail state when resource/repository identity changes; late prior requests must not publish.
4. Patient plan navigation to authorized capture details and account-wide measurement history; never infer a plan association from history or expose patient-only routes to doctors.

Preserve existing camera permissions/lifecycle, upload uncertainty, quality gate, image authorization/lease budgets, plan revision/grant checks and evaluation state machine. Tests: model validation, real controllers, bounded loading/order/partial failures/retry/timeout/account change/disposal, widget navigation/rebinding, narrow 200% text light/dark/reduced motion. Run related regressions, full Flutter tests and analyze; verify compatibility with M1/F8 source stacks. Physical camera/model/live service qualification remains external.
