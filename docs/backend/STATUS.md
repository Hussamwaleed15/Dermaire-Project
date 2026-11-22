# Backend — تقرير الحالة الرسمي

| الحقل | القيمة |
|---|---|
| Shared between people | حسام وليد؛ مراجعة مستقلة مثبتة من `salma30001-blip` على PR #4؛ تسليمات Flutter من عمرو |
| Tracks / Departments | Backend؛ AI؛ Azure/Database؛ Flutter؛ Testing/QA |
| Owner | حسام وليد |
| Documentation / Verification status | Verified للمصدر والـCI عند PR #4، وPartially verified للحالة الحالية؛ لا تحقق runtime/staging حي |
| Implementation status | In progress — API واسع ومختبر، مع gaps تكامل وتشغيل موثقة أدناه |
| Last updated | 2026-11-19 (Africa/Cairo) |
| Last verified SHA | B6-A review branch pending commit/CI; baseline `6c6255b8ef0802a28c1b9fceed222a7c9b79a50a` |

## بنعمل إيه الآن

نثبت inventory الـAPI وعقود الأمان والتكامل وprovenance، ونفصل نجاح المصدر/CI عن staging وProduction readiness.

إضافة B6-A الحالية تبني فقط طبقة reservations غير مفعلة على أي endpoint. اختبارات
SQLite نجحت، لكن PostgreSQL gate المحلي غير متاح، لذلك الحالة **In review / PG
evidence pending** وليست completion. التفاصيل والـinvariants وحدود B6-B في
[`B6_A_OPERATION_RESERVATIONS.md`](B6_A_OPERATION_RESERVATIONS.md).

## عملنا إيه — Verified

- `api_v1_router` يسجل domains المصادقة، المستخدمين، المنتجات، التجارب، check-ins، doctor، chat، baseline/context/home، PSM، measurements/safety/assistance، messaging/notifications/clinical plans/Agent: [`backend/app/api/v1/router.py`](../../backend/app/api/v1/router.py).
- Authentication يستخدم Bearer JWT مع claims مطلوبة، credential stamp، revocation، role checks وسياسة safety للعمليات الكتابية: [`backend/app/api/deps.py`](../../backend/app/api/deps.py).
- `/health/live` و`/health/build` و`/health/ready` موجودة؛ readiness يفحص DB/revision/storage/deletion journal ويفشل 503 عند عدم الجاهزية: [`backend/app/main.py`](../../backend/app/main.py).
- build provenance وrequired Alembic revision موثقان في [`backend/app/core/build_info.py`](../../backend/app/core/build_info.py). CI ينشئ source archive/dependency inventory/provenance bound to commit.
- OpenAPI gate الحالي يثبت **116 paths / 119 schemas**. فحوص Backend Core/B3/B4-B5 نجحت على head `d9edf4439fbbacb5d11f859ee48d1ea425a54f14` ثم دُمجت في [PR #4](https://github.com/Hussamwaleed15/Dermaire-Project/pull/4).

## حالة التنفيذ بالتفصيل

| المجال | Implementation status | Documentation / verification status | الحد الحالي |
|---|---|---|---|
| Routes/schemas/auth/tests | In progress | Verified من المصدر وCI المحدد | لا يثبت runtime الحالي |
| Build provenance/readiness gates | Completed في المصدر | Verified من الكود وCI | deployed artifact identity غير متحقق هنا |
| Backend ↔ Flutter contracts | In progress | Partially verified | عقود كثيرة مستهلكة؛ gaps في pagination/authorized targets/ordering/recovery |
| Backend ↔ AI | In progress / Blocked externally | Verified كـfail-closed | provider/model clinical validation غير مكتمل |
| Staging/deployment readiness | Unknown | Unknown للحالة الحية | لم تُنفذ smoke أو config/secret/resource checks في هذا الجرد |

## هنعمل إيه — أولويات حسام القابلة للقياس

1. **Contract closure:** contract tests لـAgent pagination+patient target، notification target/read ordering، وunknown/in-flight replacement semantics؛ القبول: tests سلبية للowner/revocation/concurrency وOpenAPI diff reviewed.
2. **Staging evidence pack:** عبر rollout مصرح لاحقاً فقط، ربط `/health/build` بالـSHA وAlembic head وsmoke auth/privacy؛ القبول: SHA مطابق، readiness 200، revision متوافقة، rollback rehearsal موثق. هذا التقرير لا يصرح بالنشر.
3. **CI/readiness ownership:** تسمية reviewer مستقل وowner للـQA، وتثبيت required checks + dependency/security scan + artifact retention decision؛ القبول: كل PR Backend له checks ناجحة على نفس head وموافقة مستقلة غير stale.

## Blockers / Unknowns

- current deployed SHA، staging config، provider reachability، migration revision، smoke/load/restore results: `Unknown`.
- gaps المؤكدة موثقة في [`app/docs/FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md`](../../app/docs/FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md): Agent discovery/pagination/authorized target، notification thread target/ordering، وauthoritative unknown/in-flight semantics.
- لا يُستنتج Production readiness من ملفات تاريخية أو CI فقط.

## Dependencies / Cross-track handoffs

- [تقرير التكامل المشترك](../shared/AI_BACKEND_AZURE_FLUTTER_HANDOFF.md).
- Backend يحتاج DB revision/least privilege/backup gates، وAI provider contract/version/safety، وFlutter contract consumption/negative tests.

## يحتاج مراجعة مستقلة

- Auth/privacy/concurrency contracts، OpenAPI breaking changes، migration/rollback، deployment artifact identity، والـclinical/provider boundary.

## Evidence

- [PR #4](https://github.com/Hussamwaleed15/Dermaire-Project/pull/4)، [merge commit](https://github.com/Hussamwaleed15/Dermaire-Project/commit/bf979ef99581b71314859ea3fb482c1fe79fe6fa)، و[PR #20](https://github.com/Hussamwaleed15/Dermaire-Project/pull/20) لنظام التوثيق فقط.
- [Backend Core](https://github.com/Hussamwaleed15/Dermaire-Project/actions/runs/44497060464/job/135466854756)، [B3](https://github.com/Hussamwaleed15/Dermaire-Project/actions/runs/44497060372/job/135466854372)، [B4-B5](https://github.com/Hussamwaleed15/Dermaire-Project/actions/runs/44497060343/job/135466854384).
