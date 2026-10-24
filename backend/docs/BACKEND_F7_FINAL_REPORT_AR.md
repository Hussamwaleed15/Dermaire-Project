# DERMAIRE — التقرير النهائي لدفعة Backend F7

التاريخ: 2026-10-24 — Africa/Cairo.

## النتيجة التنفيذية

بدأت الدفعة من `8a3f49dd29dcc089a2f59ae7abb350fdbf9bcc00` بعد fetch والتحقق
من تطابق `main` و`origin/main` ونظافة الشجرة. نُفذ commit المصدر والاختبارات
`7e7cd166b972af28eb60eeaf3b2c79b6ed91dbc2` ورُفع عاديًا إلى نفس
`origin/main`، ثم أُعيد fetch وتحقق التطابق. لا توجد تعديلات Flutter أو Tester أو
native، ولا Azure أو staging/production أو بيانات مرضى حقيقية.

الحالة العامة: **PARTIAL**. اكتملت عقود مهمة بالمصدر واختبارات SQLite، لكن بوابة
PostgreSQL المحلية الحقيقية كانت غير متاحة؛ لذلك لا ندعي إغلاق إثبات الأقفال
والسباقات الجديدة على PostgreSQL.

## ما نُفذ

- **B1 PARTIAL:** أضيف `Original-Grant-Id` اختياريًا لأول POST للملاحظة والمراجعة.
  عند وجوده تقفل المعاملة المريض ثم المنحة الأصلية المحددة، وتتحقق من الطبيب
  والمريض وحالة/انتهاء VIEW. المنحة البديلة لا تقبل طلبًا مربوطًا بمنحة مسحوبة.
  الرد يصرح `Original-Grant-Binding: explicit|legacy-current`. بقي مسار legacy
  للتوافق؛ لا يحصل على ضمان الربط الصريح حتى يرسل Flutter الهيدر.
- **B2 PARTIAL / ALREADY IMPLEMENTED:** حُفظت إيصالات committed الموجودة ودلالة
  unknown الصادقة. لم تُخترع حالات rejected/in-flight ولا exactly-once عامة.
  registry/fencing موحد لكل المجالات ما زال OPEN.
- **B3 DONE بالمصدر/SQLite:** `GET /agent/sessions` لاكتشاف جلسات الحساب النشطة
  ببيانات recovery دنيا فقط، وpagination ثابت. أضيف pagination لطلبات الطبيب
  و`patient_ref` مربوط بالمنحة الأصلية الحالية. سحب المنحة أو الجلسة يمنع الظهور.
- **B4 DONE بالمصدر/SQLite:** عنصر التنبيه يحمل `target` موثوقًا؛ رسالة المحادثة
  تحمل `thread_id` بعد تحقق السيرفر الحالي. أضيف `state_revision` وCAS اختياري
  بـ`expected_revision`؛ النية القديمة ترجع 412 بدل عكس نية جهاز أحدث.
- **B5 DONE بالمصدر/SQLite:** إلغاء تقييم المقارنة يقبل `Idempotency-Key` اختياريًا
  وله readback مستقل عبر operation `evaluation_cancel`. الإيصال يثبت الإلغاء
  المحدد ولا يثبت حالة تقييم أحدث.
- **B6 PARTIAL:** أضيفت اختبارات actor/patient/grant/account isolation المستهدفة،
  وبقيت مراجعة PostgreSQL الشاملة محجوبة بالبيئة.
- **B7 PARTIAL/BLOCKED:** migration جديد `20261024_14` يضيف
  `notifications.state_revision`; rehearsal SQLite وreadiness نجحا. PostgreSQL
  الحقيقي BLOCKED لأن Docker daemon غير شغال والبوابة 55441 غير متاحة.

## الاختبارات والأدلة

- baseline حقيقي منفصل عند SHA البداية: **1047 passed, 90 skipped**, 166 warnings،
  خلال 212.50s. الـ90 هي اختبارات PostgreSQL gated وليست نجاحات.
- final: **1053 passed, 90 skipped**, 166 warnings، خلال 218.45s.
- focused للعقود الجديدة: **5 passed**.
- real PostgreSQL في F7: **0 run / 90 blocked-skipped**. الرقم التاريخي 90 passed
  لا يُعاد استخدامه كدليل حالي.
- نجح SQLite seeded migration rehearsal حتى `20261024_14`، و`compileall`،
  وOpenAPI (**114 paths / 117 schemas**) و`git diff --check`.

## العقود والتوافق

كل الإضافات backward compatible: هيدر المنحة، cursor/limit، target، revision/CAS،
ومفتاح إلغاء التقييم اختيارية للعملاء القدماء. المطلوب من Amr هو تفعيل المسارات
المحصنة كما يشرح `BACKEND_F7_FLUTTER_HANDOFF.md`. لا توجد نتائج AI أو Push
مصطنعة: Agent/Comparison provider ما زالا unavailable، وPush disabled/unconfirmed.

## المتبقي

- BLOCKED: تشغيل بوابة PostgreSQL المعزولة وإعادة full + 90 PG، مع سباقات revoke
  مقابل note/review، CAS أجهزة التنبيه، pagination والإلغاء.
- OPEN: قرار إلغاء مسار clinical legacy لاحقًا أو جعله 428 بإصدار API جديد بعد
  تحديث Flutter؛ حاليًا الضمان الصريح فقط عند إرسال الهيدر.
- OPEN: registry دائم شامل للمحاولات in-flight/rejected/expired عبر كل المجالات.
- BLOCKED خارجيًا: نموذج Agent مقيد ومراجع، artifact مقارنة موثق ونقل صور آمن
  واعتماد سريري، ومزود Push فعلي مع إثبات جهاز وتسليم. لا deployment في هذه الدفعة.

ملفات التسليم: `BACKEND_F7_CONTRACT_MATRIX.md` و
`BACKEND_F7_FLUTTER_HANDOFF.md` وهذا التقرير. SHA النهائي وcommit التوثيق يُبلغان
في رسالة التسليم الخارجية بعد commit، لتجنب مرجع ذاتي داخل commit نفسه.
