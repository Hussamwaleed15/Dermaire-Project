# DERMAIRE Foundation closure — تسليم مستقل لعمرو

تسليم HTTP من المصدر المختبر؛ لا يوجد تعديل أو اختبار Flutter/Android/iOS/Tester أو أجهزة. مسارات الأساس `/api/v1`. العقود غير المعدلة تبقى في H2_COMPLETION_AMR_API_HANDOFF.md وH3_FLUTTER_CONTRACT_HANDOFF.md وH4_FLUTTER_HANDOFF.md. أمثلة JSON الكاملة الناتجة عن طلبات حقيقية على PostgreSQL اصطناعي مرفقة في FOUNDATION_API_SYNTHETIC_EXAMPLES.json؛ لا تتضمن Bearer tokens أو بيانات حقيقية.

## 1. وصف يوم الروتين — إضافي، وليس تغيير تقويم

GET `/routine/entries` وGET/PATCH `/routine/entries/{entry_id}` وPOST `/routine/entries` تضيف `day_provenance`:

```json
{"schema_version":1,"calendar_zone":"UTC","zone_source":"server_utc_contract","naive_timestamp_basis":"UTC","slot_semantics":"user_reported_not_wall_clock","configuration_recorded_at":"2026-10-15T12:00:00Z","earliest_report_date":"2026-10-15","history_basis":"latest_configuration_only"}
```

هذا مثال اصطناعي للجزء الجديد فقط. `earliest_report_date` يصف حد الإعداد الحالي، ولا يضمن قبول كل يوم/slot؛ فحماية التجربة والتوقف والتكرار تبقى. AM/PM إبلاغ المستخدم وليست مواعيد بالساعة. لا تحول YYYY-MM-DD إلى يوم الجهاز أو القاهرة، ولا تحول السجل التاريخي. لا يوجد تفضيل منطقة زمنية للمستخدم أو API لجدولة DST. تُحفظ الإضافة داخل configuration_snapshot للالتزامات الجديدة؛ غيابها من اللقطات القديمة يعني أنها قديمة، ولا يُملأ ببيانات اليوم. لا تغيير لواجهات adherence أو receipt أو CAS أو 412/428.

## 2. حداثة PSM والتاريخ

GET `/personal-skin-model` يبقى schema_version2 وderivation_version psm-v2.0؛ هذه إصدارات خوارزمية/عقد وليست revision لقاعدة الأدلة. إضافة `source_read_consistency` في الواجهة المنفصلة = `multiple_reads_not_atomic_snapshot`. إضافة `sufficiency.freshness` بالعقد القائم schema1/as_of/latest_at/basis elapsed_UTC_duration/threshold_days14/age_days_basis UTC_calendar_difference/state/age_days. `sufficiency.recency` الآن يستخدم المدة:14 يومًا بالضبط fresh؛14 يومًا وثانية stale، مع بقاء age_days التقويمي14. هذا تقادم هندسي لا صلاحية سريرية.

كل finding يضيف `earliest_evidence_at` و`freshness_basis:"latest_referenced_evidence"`؛ حداثة أحدث دليل لا تعني أن كل المراجع حديثة. غياب الأدلة والمستقبل لا يثبتان الحداثة أو السلامة.

GET `/routine/adherence/history?limit=100&routine_entry_id=...&cursor=...` يحتفظ بعقد H4. حد1–500، ترتيب created_at DESC,id DESC، مدة المؤشر ساعة واحدة من الصفحة الأولى، تغيير limit مسموح وتغيير الفلتر يتطلب إعادة البدء.401 للمصادقة،404 لفلتر لا يملكه الحساب،422 للتلاعب/اختلاف الحساب أو الفلتر/المؤشر غير السليم،410 للانتهاء. now/cutoff ليستا MVCC snapshot، وقد يظهر التزام متأخر بطابع قديم أو يختفي سجل مُحي. لا تستخدم as_of لإعادة بناء حالة سريرية تاريخية. واجهة offset القديمة باقية.

## 3. إيصال إنشاء المنتج فقط

قبل أول إرسال، احفظ محليًا وبشكل منفصل لكل حساب: مسودة ProductCreate الطبيعية، مفتاحًا عشوائيًا ثابتًا للمحاولة، وحالة المصالحة. المفتاح16–128 محرف ASCII من الحروف والأرقام و`_` و`-`، مثل `synthetic-product-example-0001` في الأمثلة فقط. لا تضع بيانات صحية أو رمز جلسة في المفتاح.

```http
POST /api/v1/products
Authorization: Bearer <access-token>
Idempotency-Key: <persisted-random-attempt-key>
Content-Type: application/json

{"name":"Synthetic moisturizer","in_routine":false}
```

201 مع ProductOut القديم كاملًا، و`ETag: "1"` و`Operation-Attempt-Id` و`Cache-Control:no-store`. بدون Idempotency-Key يبقى الإنشاء القديم ولا يوجد ضمان محاولة. التكرار بنفس المفتاح والطلب الطبيعي يعيد النتيجة الأصلية و201 وETag الأصلي؛ تغير النص/null/ترتيب القوائم يُعد طلبًا مختلفًا، والطوابع start_date تُطبع إلى UTC. لا تعتمد على إعادة ترتيب القوائم أو تغيير مسودة بعد إرسالها.

```http
GET /api/v1/products/attempts/<same-key>
Authorization: Bearer <same-account-access-token>
```

200 مع schema_version1،operation product_create،attempt_id،owner_id،actor_id،status،result_availability،resource_id،resource_revision،recorded_at،expires_at،result. الحقول غير المتاحة null. الحالات:

| status / availability | الإجراء |
|---|---|
| unknown / unknown | لا يثبت الفشل؛ قد تكون الكتابة جارية. أعد نفس POST بالمفتاح والمسودة نفسيهما ضمن النافذة؛ لا تنشئ مفتاحًا جديدًا لتجاوز الغموض |
| committed / retained | result هو ProductOut الأصلي وrevision1، وليس الحالة الحالية. أثبت نجاح الإنشاء، ثم GET المنتج لتحديث العرض وETag الحالي قبل تعديل جديد |
| committed / erased | ثبت الإنشاء الأصلي، لكن محتوى النتيجة مُحي مع المنتج؛ result=null، وPOST بنفس المفتاح410 دون إعادة الإنشاء |
| expired / expired | نافذة30 يومًا من recorded_at انتهت؛ result=null مع معرّف المورد والوقت. POST410 ولا يعاد الإنشاء بالمفتاح نفسه؛ صالح السجل/المورد الأصلي |

رد 409 يعني اختلاف الطلب عن المفتاح أو تعارض اسم المنتج الحالي؛ لا تبدّل المحتوى وتعيده بالمفتاح القديم.422 لطلب/مفتاح غير صالح أو تكرار Header.401 انتهاء/إلغاء الجلسة؛403 لسياسة السلامة الحالية عند تفعيلها قبل كتابة أو replay.503 نتيجة غير مؤكدة، وليس رفضًا دائمًا؛ استخدم lookup ثم نفس المحاولة. فشل GET لا يتحول إلى unknown ناجحة. حساب آخر يرى unknown الخاص به ولا يرى إيصال المالك.

لا تكتب نتيجة replay ذات revision1 فوق نسخة أحدث في cache، ولا تعرضها كمنتج حالي بعد حذف المنتج. GET المنتج قد يعيد404 مع استمرار إثبات الإنشاء. حذف المنتج يمحو result_snapshot ويترك إثباتًا محدودًا؛ محو الحساب يمحو محاولاته. نافذة الوصول30 يومًا لا تعني مهمة حذف تلقائي؛ لا scheduler جديد. لا يوجد rejected أو in_flight دائم، ولا ضمان exactly-once للكتابات بلا مفتاح/الآثار الخارجية. PATCH/DELETE المنتجات وإعداد الروتين والتجارب والسريريات والمنح ليست مشمولة بإيصال جديد؛ احتفظ بمعالجة CAS الحالية ولا تفترض أن GET المورد يثبت محاولة بعينها.

## 4. قراءة سريرية مجمعة للمريض على PostgreSQL

```http
GET /api/v1/clinical-snapshot
Authorization: Bearer <patient-access-token>
```

200 typed schema1 يحوي snapshot_id،patient_id،evaluated_at،consistency `postgresql_repeatable_read_transaction`،atomic_scope `database_rows_visible_in_one_transaction`،external_sources `not_fetched_not_atomic`،replayable false،clinical_clearance false،safety،review،home،personal_skin_model،limitations. الأجزاء تشترك في وقت تقييم وSafety واحدين داخل معاملة PostgreSQL ثابتة. evaluated_at ليس commit watermark؛ snapshot_id معرّف ربط، وليس token لإعادة الطلب أو التاريخ. لا يوجد query as_of أو endpoint لاسترجاع معرّف سابق.

استخدم أجزاء الرد الواحد معًا، واربطها بالحساب صاحب الطلب. لا تخلط bundle مع GET منفصل أو حساب آخر أو رد أقدم. الواجهات المنفصلة تحتفظ بعقدها غير الذري. لا يشمل الضمان ملفات الصور أو AI أو مزودًا خارجيًا أو تغييرات التزمت بعد snapshot. سلطة Safety العاجلة محفوظة فوق PSM أو توصية أقل، والقرار الحالي الخاص يظهر غير متاح دون إحلال قرار عام أقدم مكانه. تاريخ القرارات العامة يظل تاريخيًا.

401 للمصادقة الحالية،403 لأي مستخدم غير المريض حتى مع منحة طبيب،503 عند غياب PostgreSQL أو تعذر العزل/القراءة/القفل/serialization؛ لا يعاد جزء من bundle. لا تحوّل503 إلى حالة مطمئنة أو نجاح. الواجهة patient-only؛ الطبيب يستمر في مسارات H1/H3 الحالية التي تعيد فحص VIEW والمنحة. Cache-Control no-store وPragma no-cache. بعد تغيير المصادر اطلب bundle جديدة؛ لا يعد وجود رد سابق إثبات حداثة حالية.

## 5. ترتيب الدمج والطرح المستقبلي

1. في بيئة مفوضة لاحقًا فقط: تحقق النسخ الاحتياطي/الاستعادة وسجل المحو والنسخة الحالية، ثم الهجرة20261015_03 بعد20261015_02 قبل إصدار Backend الجديد. لم تُنفذ هجرة أو عملية نشر مُدارة هنا.
2. اختبر API والعقود على قاعدة البيئة المقصودة؛ SQLite لا يدعم ادعاء snapshot هذه الواجهة ويعيد503. لا توجد راية تفعيل جديدة. شرط SAFETY_POLICY_ENFORCE وموافقة H3 لم يتغيرا.
3. استهلك الحقول الإضافية بتوافق قديم؛ فعّل تجربة إيصال الإنشاء لكل حساب مع حفظ المفتاح قبل أول إرسال. لا تعممها على عمليات أخرى.
4. استهلك bundle المريض كوحدة واحدة، مع حالات loading/error/unknown والتبديل بين الحسابات دون تسرب cache. أكمل اختبارات Amr على Android/iOS بشكل مستقل؛ لم تُختبر الأجهزة هنا.

اختبارات الدمج المطلوبة لعمرو: timeout بعد commit ثم restart/lookup؛ unknown ثم same-key POST؛ اختلاف المسودة409؛ expiry/erased410؛ تعديل المنتج ثم replay دون إفساد ETag الحالي؛ logout/account switching؛ سياسة موافقة جديدة؛ مؤشر history من حساب/فلتر آخر؛ UTC midnight وDST دون تحويل يوم السجل؛ private current decision مع public history؛ urgent Safety مع توصية أقل؛ فشل snapshot دون clearance. H1 VIEW مقابل EXPORT الصريح،H2 check-in/adherence/CAS،H3 onboarding/policy/provenance،H4 capture/experiment/evidence تبقى كما في التسليمات السابقة. لا H5 ولا إشعارات/مواعيد/متابعة/تشخيص أو مقارنة صور جديدة.
