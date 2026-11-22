# Azure / Infrastructure / Database — تقرير الحالة الرسمي

| الحقل | القيمة |
|---|---|
| Shared between people | حسام وليد؛ المراجع الأمني/التشغيلي المستقل `TBD` |
| Tracks / Departments | Azure / Infrastructure / Database؛ Backend؛ AI |
| Owner | حسام وليد |
| Documentation / Verification status | Partially verified من الملفات والتاريخ؛ لا يوجد live verification في هذا الجرد |
| Implementation status | In progress تاريخياً؛ current live state Unknown |
| Last updated | 2026-11-19 (Africa/Cairo) |
| Last verified SHA | [`62893d13dd1558d1c689297f8e23ced8e24fbdc4`](https://github.com/Hussamwaleed15/Dermaire-Project/commit/62893d13dd1558d1c689297f8e23ced8e24fbdc4) |

## بنعمل إيه الآن

نفصل بين ما تنفذه الملفات وما سجلته تقارير rollout التاريخية وما هو مرصود حياً الآن. لم يدخل هذا الجرد Azure، ولم يتصل بقاعدة بيانات، ولم يشغل migrations.

## عملنا إيه — Verified من المستودع

- PostgreSQL 18 هو gate الـCI، مع `statement_timeout` وUTC وpool pre-ping في [`backend/app/core/database.py`](../../backend/app/core/database.py).
- Alembic موجود وله سلسلة migrations حتى revision المطلوبة `20261024_14`: [`backend/migrations/versions/`](../../backend/migrations/versions/) و[`backend/app/core/build_info.py`](../../backend/app/core/build_info.py).
- Dockerfile وdocker-compose يقدمان packaging/local environment؛ لا يثبتان Azure deployment أو deployed manifest.
- readiness يفحص DB schema compatibility وBlob وdeletion journal، وmanaged environments لا تنشئ schema تلقائياً.
- توجد runbooks وقوالب least-privilege وrestore/rollback/monitoring، وتقارير rollout تاريخية. هي evidence تاريخي وليست live inventory بتاريخ هذا التقرير.
- لم يُعثر على Terraform/Bicep/ARM deployment source كـIaC authoritative في الشجرة؛ drift reproducibility غير مكتملة.

## حالة التنفيذ بالتفصيل

| المجال | Implementation status | Documentation / verification status | الحد الحالي |
|---|---|---|---|
| Alembic migrations + schema gate | Completed في المصدر | Verified من الملفات/CI؛ live revision Unknown | لم تُشغل migration هنا |
| DB least privilege/TLS/runtime role | Implemented/Planned تاريخياً | Needs re-verification | القوالب والتقارير لا تثبت الوضع الحالي |
| Deployment manifests/IaC | Unknown / gap | Partially verified | Docker assets موجودة؛ لا IaC authoritative مكتشف |
| Backup/PITR/deletion journal | In progress تاريخياً | Needs re-verification | freshness/coverage الحالية Unknown |
| Restore/RTO rehearsal | Blocked كاعتماد جاهزية | Partially verified تاريخياً | آخر تقرير يصرح أن end-to-end RTO ≤30m غير certified |
| Monitoring/alerts/cost | In progress تاريخياً | Needs re-verification | لا live alert delivery/cost budget/ownership check |
| Azure AI/provider resources | Unknown حياً | Unknown | لا provider reachability أو quota/cost check |

## هنعمل إيه — أولويات حسام القابلة للقياس

1. **Read-only live inventory منفصل ومصرح:** metadata منزوعة الأسرار للresources/settings names/identities/networking/DB revision/backup/alerts؛ القبول: 100% من environments لها owner، purpose، region، drift status وevidence.
2. **Recovery gate:** fresh backup + isolated restore rehearsal + deletion-journal reconciliation وقياس RPO/RTO؛ القبول: restore إلى target منفصل، schema/grants verified، tombstone replay، وRTO/RPO مقاسان ومراجَعين. لا يُنفذ من هذا PR.
3. **IaC/security/cost gate:** تحويل الموارد الأساسية إلى reviewed IaC أو توثيق الاستثناء، ثم plan-only diff وpolicy checks؛ القبول: no public/unscoped secrets، least-privilege runtime/migrator split، budgets/alerts/retention owners، وdrift صفر أو مقبول صراحة.

## Blockers / Unknowns

- live resources/deployments/database revision/backups/monitoring/cost/provider state: `Unknown`.
- لا يجوز نقل الادعاءات التاريخية إلى الحالة الحالية بلا timestamp ودليل حي جديد.

## Dependencies / Cross-track handoffs

- [تقرير التكامل المشترك](../shared/AI_BACKEND_AZURE_FLUTTER_HANDOFF.md).
- Backend يعتمد على schema revision/readiness/rollback؛ AI يعتمد على provider/data boundaries؛ كلاهما يحتاج cost/security/monitoring ownership.

## يحتاج مراجعة مستقلة

- IaC plan/security architecture، DB migration/restore، RBAC/managed identity، backup privacy/tombstone behavior، alert delivery والتكلفة.

## Evidence

- [`docs/production-release-runbook.md`](../production-release-runbook.md)، [`docs/production-phase5-complete-20261009.md`](../production-phase5-complete-20261009.md)، [`docs/least-privilege-postgresql.sql`](../least-privilege-postgresql.sql). مراجع تاريخية/قوالب؛ لا تثبت الوضع الحي الحالي.
