# Backend master status after H4 — 2026-10-15 Cairo

Current source ledger; supersedes H3_BACKEND_MASTER_STATUS only for work delivered by H4. DONE means local source/test verification, not deployment. Historical H0/H2/H3 reports remain evidence of their own checkpoints, not current rollout approval. H5 has not started.

| Milestone / domain | Status | Verified boundary / remaining |
|---|---|---|
| H4-F1 routine/adherence temporal consistency | PARTIAL | Explicit UTC day basis/history limit; aware timestamp normalization; frozen adherence/CAS preserved. No user timezone preference/DST scheduling or complete routine revision event stream |
| H4-F2 experiment provenance | DONE bounded typed/frozen contract; legacy completeness PARTIAL | Score unit, source, aggregation, direction, evaluation algorithm and recorded/missing/mixed measurement versions frozen. Mixed image versions cannot support directional label. Historical missing metadata remains unknown; no calibration/clinical validation |
| H4-F3 capture/observation association | DONE explicit bounded link | Patient-owned accepted capture + validated structured observation selection/retraction; current doctor VIEW reauthorization; no inferred association, image inference, comparison or general attempt receipt |
| H4-F4 freshness/history | PARTIAL | Typed PSM finding freshness, explicit source freshness time/basis/threshold, future unknown; signed account/filter-bound adherence keyset history. All-domain stable histories and atomic clinical source snapshot OPEN |
| H4-F5 integration | DONE isolated gate; folder cleanup PARTIAL | 912 passed,41 real PG cases; SQLite/PG migrations/security/concurrency/full regression; standalone Amr Android/iOS HTTP handoff. Service stopped; policy blocked deleting stopped data folder. No mobile/device or managed-environment certification |
| H1 QR consent/authority | DONE existing local subset preserved | VIEW/EXPORT consent, revocation/expiry/doctor binding retained; no new export endpoint |
| H2 Product/Routine/Experiment revisions | DONE existing protected subset preserved | Existing CAS/ETag guards retained, no duplicate revision system |
| H2 general durable operations | OPEN / PARTIAL | Existing report/manual and adherence committed/unknown/expired subsets retained; rejected/in-flight durability absent. Product/routine config/experiment/clinical/grant operations still lack generalized atomic durable receipts/tombstones; link selection is not such a receipt |
| H3 policy/onboarding | DONE source; live rollout OPEN | Version-aware policy and explicit optional profile review retained; enforcement default unchanged; current policy enforced on new writes when configured |
| H3 atomic clinical snapshot | OPEN | H4 cutoff/cursor is not an atomic source snapshot or clinical ETag |
| Managed migration, backups/restore, rollout/DR | BLOCKED by separate environment authorization/verification | No live calls, config changes, migrations, deployment or production-readiness claim |
| Autonomous Agent, diagnosis, validated real image comparison, scheduled followups, messaging/notifications | OPEN / out of this wave | No fabricated medical semantics, models or schedules |

One new migration:20261015_02 after20261015_01, capture_observations table, no historical backfill, populated downgrade refusal. New code requires this schema before a separately authorized rollout. Existing consent flags and all protected resource defaults unchanged.

Next backlog remains: per-domain durable attempts with business/audit/receipt atomicity and privacy-safe erasure; explicit consistent clinical source set/snapshot and stable histories; full routine history/user timezone specification before calendar cutover; separately authorized managed migration/backup/restore/monitoring verification. New messaging/appointments/followups need product/privacy/clinical specification. This ledger does not authorize H5.

Contracts: H4_FLUTTER_HANDOFF.md, H4_SOURCE_SCOPE.md, H4_F1_TEMPORAL.md, H4_F2_METRIC_PROVENANCE.md, H4_F3_CAPTURE_OBSERVATIONS.md, H4_F4_HISTORY_FRESHNESS.md, H4_F5_REGRESSION.md. Previous H2/H3 handoffs remain for unchanged endpoints.
