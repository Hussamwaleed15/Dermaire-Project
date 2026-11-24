# M3 implementation checkpoint —14 November2026

Base main b995873f2b76e0c37a08f23fbf40322174aba6fe, freshly fetched. PR6–8,9–10,11 remain separate open stacks. All required PSM/contextual assistance/clinical source exists on main. Return experience is scoped to the existing PSM route, not a duplicate Home priority engine; no M1/M2/F8 code imported.

Read canonical Master Plan v1 from PR10 (not yet on main), app/AGENTS.md, PSM2 projection/enrichment/freshness and contextual-ai request/response/provider contracts. Reconcile seven M3 requirements in final report.

Demonstrated gaps to close:
1. Supported daily-context, routine and product projection absent from PSM presentation; add bounded typed read-only source sections, partial failures independent of Safety.
2. Backend unknown freshness state rejected; source age/latest/finding freshness not displayed. Preserve server labels, never calculate clinical freshness locally.
3. Clinician snapshot lost when PSM refresh fails, despite independent urgent recommendation. Retain explicitly stale warning only within original session; current clinical readback separate. Surface snapshot above lower-priority evidence; never authorize from cache.
4. Open PSM route does not refresh on resume; implement invalidation and bounded welcome-back status with no missing-day inference or scheduler. Preserve safety warnings and user choice; no autonomous action.
5. Assistance permits inferred_points with non-grounded provider mode and ignores contradictory metadata. Validate source claims, retain moderation as separate nonclinical metadata; no provider activation.
6. PSM/assistance widget identity reuse and assistance background responses can retain superseded private content. Rebind controllers, fence late responses, clear assistance snapshot on background with no automatic POST replay.

Tests: real parsers/controllers/widgets, malformed/partial/future source metadata, stale retained warnings, resume/expiry/switch/dispose/rebind, no auto assistance resubmit, narrow200%light/dark/reduced motion. Full relevant/full suite/analyze and disposable M1/M2/F8 compatibility. No Backend/native/Tester/provider/policy changes or live services. No broadened Agent allowlist.
