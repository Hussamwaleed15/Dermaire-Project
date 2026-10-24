# DERMAIRE — التقرير النهائي لدفعة Backend F8

التاريخ: 2026-10-24 — Africa/Cairo.

## النتيجة

بدأت F8 من SHA `7acaa4bd900613835e08cc7d5619732484f94afa` مع شجرة نظيفة
وتطابق كامل مع `origin/main`. لم تظهر commits جديدة من زميل أثناء التنفيذ.

الحالة العامة: **DONE لنطاق الاعتمادية المحلي القابل للتنفيذ، وPARTIAL للمنتج
الكامل بسبب الاعتماديات الخارجية AI/Push/clinical validation**.

شُغلت قاعدة PostgreSQL 18 جديدة ومعزولة لهذه المحادثة فقط على
`127.0.0.1:55441` باستخدام التوزيعة المحمولة الموجودة محليًا. لم تُستخدم قاعدة
حية أو Azure أو staging/production أو بيانات مرضى حقيقية، ولم يحدث تغيير privileged.

## مشكلة PostgreSQL المكتشفة والإصلاح

أول full run حقيقي أعطى `1137 passed, 6 failed` خلال 325.13 ثانية. كانت الحالات
الست هي clinical receipt/revoke races. السبب الفعلي: تعريف `Original-Grant-Id`
باستخدام قيمة `Header(...)` كـdefault جعل الاستدعاءات المباشرة للخدمة بدون الهيدر
تمرر FastAPI descriptor إلى SQLAlchemy؛ SQLite لم يكشف النوع، بينما psycopg رفضه.

حُول التعريف إلى `Annotated[..., Header(...)] = None`. بقي عقد HTTP نفسه تمامًا،
وأصبح الاستدعاء المباشر يملك default حقيقيًا. بعد الإصلاح نجحت حالات الفشل الست.

## التأهيل الأمني والذرية

- **DONE:** note/review مقابل revoke في ترتيبي السباق الفعليين على PostgreSQL.
- **DONE:** المنحة الأصلية المسحوبة لا تُستبدل بمنحة أحدث عند إرسال
  `Original-Grant-Id`، للملاحظات والمراجعات.
- **DONE:** duplicate idempotency key يتسلسل إلى سجل وإيصال واحد، وتعارض payload
  يبقى 409، وفشل commit يرجع المعاملة كاملة.
- **DONE:** review CAS وunique sequence الفعليان.
- **DONE:** Agent session discovery account isolation على PostgreSQL.
- **DONE:** notification state revision/CAS على PostgreSQL.
- **DONE:** evaluation cancellation receipt/readback على PostgreSQL.
- **DONE:** migrations seeded upgrade وAlembic drift، والأقفال/lock timeout/deadlock
  detection، والـworker leases وrollback ضمن المجموعة الكاملة.
- **PARTIAL:** `legacy-current` ما زال متاحًا للتوافق ولا يملك ضمان المنحة الأصلية؛
  Flutter يجب أن يرسل الهيدر. لم يُحذف المسار القديم دون موافقة انتقال منفصلة.

## نتائج الاختبارات النهائية

- full Backend + real PostgreSQL: **1148 passed, 0 failed, 0 errors, 0 skipped**،
  خلال 326.62 ثانية، مع 217 dependency warnings.
- عدد اختبارات PostgreSQL الفعلية gated: **95 passed** (90 الحالية السابقة + 5
  حالات F8 جديدة)، كلها على قواعد disposable جديدة مستقلة.
- focused لإصلاح حالات الفشل: **6 passed**.
- focused لحالات PostgreSQL الجديدة: **5 passed**.
- `compileall`: ناجح.
- Alembic head: `20261024_14`، ولا migration جديد في F8.
- OpenAPI: 114 paths و117 schemas.
- `git diff --check`: ناجح.

## Operation recovery

الحالة **ALREADY IMPLEMENTED/PARTIAL**: الإيصالات الحالية تثبت committed الأصلي
وتحفظ actor/account/patient/grant/payload/key حيث يدعم المجال ذلك. `unknown` لا
يعني rejected أو safe-to-retry. لم يُضف F8 registry عام شكلي لحالات in-flight أو
rejected لأن المعنى الدائم عبر crash/rollback غير متوفر لكل المجالات، ولم يُدعَ
exactly-once.

## AI Agent والمقارنة

الحالة **BLOCKED خارجيًا**. المصدر الحالي يملك typed fail-closed provider
envelopes، config validation، HTTPS/credential pairing، timeout bounds، context
ownership، tool/session budgets، comparison leases/retry limits، artifact/version
provenance، human review وSafety boundaries. لا توجد credentials أو permissions أو
validated comparison artifact أو clinical validation تسمح بربط مزود حقيقي. بقيت
الحالة truthful: unavailable، دون تشخيص أو نسبة تحسن أو approval مصطنع.

## Push

الحالة **PARTIAL محليًا / BLOCKED فعليًا**. التسجيل يربط token بالحساب والجلسة
والموافقة، يخزن token مشفرًا ويمنع نقله بين حسابين نشطين. الـoutbox يطبق dedup،
leases، retry/backoff، unknown للـlease المنتهي، revocation fences وحمولة عامة بلا
PHI. المزود الافتراضي disabled ولا يوجد provider credential أو جهاز لإثبات
delivery؛ provider acceptance لا يساوي device delivery.

## Git والنطاق

Implementation commit:
`7706c6a76c1947ecf71b5f1a86bcbde3fe224a41`.

الملفات المعدلة في milestone المصدر:

- `backend/app/api/v1/doctor.py`
- `backend/tests/test_clinical_attempts.py`
- `backend/tests/test_agent_platform.py`
- `backend/tests/test_notifications.py`
- `backend/tests/test_clinical_plans.py`

لم تُعدل Flutter أو Tester أو native أو infrastructure. SHA النهائي وcommit
التوثيق يبلغان في التسليم الخارجي بعد إنشاء commit لتجنب مرجع ذاتي.
