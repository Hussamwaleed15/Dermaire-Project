# تقرير Dermaire Flutter F6-P —2026-10-19

الحالة الإجمالية: **PARTIAL**. نُفذت ست دفعات فعلية، كل دفعة اجتازت التحليل
ومجموعة الاختبارات الكاملة قبل رفعها. لا يمثل ذلك إكمال F6 كله، أو إثبات عمل
Production أو سلامة الأجهزة الفعلية.

## Git والنطاق

- البداية الفعلية: `745b26ee5224632fe121ccde31d6bd6091d757c7`، فرع main نظيف
  ومتطابق مع origin/main بعد الفحص والجلب.
- آخر SHA للتنفيذ والاختبارات: `5c6c8acb063ae64aff3107db1cdeb675bcb11119`.
  تحققنا أن remote main يساويه حرفيًا، وأن شجرة العمل نظيفة.
- يلي هذا SHA التزام توثيقي لإضافة هذا التقرير فقط؛ SHA النهائي لذلك الالتزام
  يُسلّم في رد الإغلاق، لتجنب وصف SHA سابق بأنه آخر التزام في المستودع.
- origin fetch/push: `https://github.com/Hussamwaleed15/Dermaire-Project.git`.
- قبل كل دفعة جرى جلب main وفحص عدم وجود تغييرات متزامنة؛ الرفع عادي دون
  force أو إعادة كتابة التاريخ. لم توجد تغييرات أخرى تستدعي الدمج.
- كل التعديلات تحت app/lib وapp/test وapp/docs. فحص الفرق أكد عدم تغيير
  backend أو app/android أو app/ios أو Tester. لا تشغيل أو اتصال بخدمات
  Production/Staging أو حسابات حقيقية، ولا OAuth حقيقي أو deployment.

الدفعات الست المرفوعة:

```text
e4adfd91a5156816fc22a685a67900037bfcf2c6 feat(flutter): connect patient care navigation and truthful account actions
ed88c06c88ee756259d16dd4bd9e88c15a9f2f62 feat(flutter): integrate prospective routine history and calendar policy
120a63ef4a5d2197bc0da6a72b020765c7f214bb fix(flutter): isolate doctor care routes and quarantine grant-lost drafts
8f7a012c64b049d05d304ecb7ffc1b5cf58a806a feat(flutter): review routine and experiment receipts from original metadata
edae5447a9f91d11acaffa71cece03c1fb947a81 fix(flutter): preserve guided capture when opening plans from inbox
5c6c8acb063ae64aff3107db1cdeb675bcb11119 test(flutter): connect clinician note and patient care journeys
```

## ما نُفذ

| المرحلة | الحالة | النتيجة الفعلية |
|---|---|---|
| P0 | DONE | فحص المصدر والعقود الحالية وتوثيق جرد الوظائف وأولويات التنفيذ في FLUTTER_F6_P_EXECUTION.md |
| P1a | DONE ضمن النطاق | إعادة زر الكاميرا الأوسط، الحفاظ على مؤشرات التبويبات الستة، تنقل قابل للوصول والنص الكبير؛ ربط Home بالرعاية مع إعادة قراءة السيرفر بعد الرجوع؛ إزالة نجاحات التصدير/الإتاحة الوهمية وربط إعدادات فعلية |
| P1b | DONE ضمن النطاق | عرض التاريخ المستقبلي المسجل لتغييرات الروتين مع cursor وترتيب ومصدر الأدلة؛ سياسة المنطقة الزمنية عبر CAS وموافقة صريحة، وتأكيد مستقل، دون إعادة تسمية التاريخ أو تعديل التذكيرات تلقائيًا |
| P2/P3 | DONE للإصلاحات المحددة / PARTIAL للمراجعة الشاملة | تنقل الطبيب إلى محادثات وخطط المريض المحدد، عرض الصلاحيات التي أعادها السيرفر فقط؛ إزالة المحتوى عند تغير السياق، وإعادة إنشاء القوائم عند تبديل المريض؛ مسح المسودات عند فقد المنحة والاحتفاظ بالهوية الدنيا للعمليات غير المؤكدة |
| P4 | PARTIAL | قارئا إيصالات إضافيان للروتين والتجارب، ومراجعة فعلية من الهوية الأصلية في الواجهة؛ اختبار SQLCipher على قرص حقيقي مع منصة مفاتيح وهمية؛ بقية مجالات الاسترجاع لها حدود موثقة |
| P5 | DONE للإصلاحات المحددة / PARTIAL لكل المنتج | إصلاح فتح المقارنة من الإشعارات بحيث تحتفظ بإمكانية الكاميرا؛ بطاقة الخطوة التالية بحسب حالة الخطة والدور دون نسبة شفاء أو اكتمال زمني مختلق |
| P6 | PARTIAL للرحلة الشاملة | توسيع رحلات الطبيب الفعلية بين Snapshot والملاحظة والمحادثة والخطة والأدلة وسحب الوصول؛ اختبارات الرحلات السابقة محفوظة؛ لا ادعاء رحلة واحدة تغطي19 خطوة مريض و12 خطوة طبيب بالكامل |
| P7 | DONE للتحقق من المصدر | تحديث حالة التنفيذ وجدول مختصر عملي لحسام بعد مراجعة المسارات والخدمات الفعلية |

التصميم بقي English-only وCream/Ivory/Burgundy في اللايت وCharcoal/Graphite/Rose
في الدارك. حافظنا على تقليل الحركة، ترتيب القراءة، semantics والنص الكبير.
التحسينات داخل Flutter الحقيقي، دون mockups أو إعادة تصميم الشاشات المستقرة.

## رحلات المريض والطبيب

**المريض:** الدخول وبوابة الموافقة المرجعية من السيرفر مستمران. Home يتيح
المحادثات والخطط والمنح والإشعارات وAgent، وتُقرأ الإسقاطات الحالية بعد العودة.
يمكن الوصول لتاريخ الروتين والسياسة الزمنية من Routine وReports والتاريخ.
عند فتح إشعار لخطة، يُقرأ كيان الخطة الحالي؛ نسخة الإشعار القديمة ليست سلطة
على حالتها. المقارنة المجدولة تتيح التصوير؛ الملغاة أو المسجل لها review لا
تطلب التقاطًا جديدًا. الخروج يمسح العرض الخاص.

**الطبيب:** اختبارات الدور/theme/حجم الخط تشمل الدخول والموافقة، المحادثات
وإرسالها/قراءتها، الخطط والإشعارات وطلبات Agent، ثم اختيار المريض وSnapshot،
حفظ ملاحظة وقراءة تأكيدها، فتح محادثة وخطة نفس المريض، الأدلة، وفقدان الصلاحية
والخروج وتغيير الحساب. إنشاء الخطط وإعادة جدولتها ومراجعة المقارنات لها اختبارات
مجال مستقلة موجودة؛ لم ندمج كل ذلك في مسار واحد جديد ولم ندّعِ Backend E2E.
اختبارات Products/Routine/Adherence/Experiments/PSM/Observation/Guided Capture
الموجودة بقيت ضمن المجموعة الكاملة؛ هذا لا يساوي إثبات كل الرحلة على جهاز.

## الخصوصية والعمليات غير المؤكدة

- تبديل المريض لا يعيد استخدام controller قائمة محادثات/خطط المريض السابق.
- صفحات الرعاية المرتبطة باتصال الطبيب تُخفي شجرتها الخاصة إذا فُقد السياق
  أو تغيرت المنحة. لا تعيد اختيار المريض تلقائيًا لإحياء صلاحية قديمة.
- عند فقد المنحة، تُزال مسودة note/review وذاكرة receipt الخام، وتبقى هوية
  محدودة: المالك والدور والمسار والمفتاح والبصمة ومعرفات/revisions مسموحة.
- رد متأخر يمكنه إضافة معرف نتيجة موثوق فقط إذا تطابق المريض والطبيب والمنحة؛
  لا يعيد السرد الطبي أو المحتوى للواجهة. الطلب البديل يبقى محظورًا.
- VIEW لا تعني EXPORT، ولا وجود لادعاء توثيق رخصة أو تصدير غير منفذ.
- اختبارات denied-read القديمة أصبحت تتطلب مسح المحتوى عند403 أيضًا، مع حفظ
  الهوية؛503 لا يُفسر تلقائيًا كسحب صلاحية. لم تُحذف تأكيدات النتائج لتنجح الفحوصات.
- لم نُضف طباعة tokens أو صور أو سرد طبي. الأخطاء المعروضة مختصرة ومطهرة.

## الاسترجاع المشفر: ما الذي أُثبت وما الذي لم يُثبت؟

**IMPLEMENTED SOFTWARE:** SQLCipher ودورة المفاتيح الأصلية من F6-N محفوظان.
أضيف دعم قراءة ConfigurationAttempt للروتين والتجارب من الهوية الدنيا، دون
استعادة body أو إنشاء key جديد. يوجد قارئ المنتجات السابق. lookup يتحقق من
المالك والفاعل والمجال والعملية والكيان والنسخة وDTO. الحالة الحالية قراءة منفصلة.
تفعيل التجربة والتقييم يحتاجان مراجعة الحالة المرتبطة؛ لا نعتبر receipt دليلًا
على أن كل الروتين والمنتج أو النتيجة المشتقة ما زالت حالية.

**TESTED RECOVERY:** اختبارات isolated للعقود والواجهة، وفتح قاعدة SQLCipher
حقيقية وإغلاقها وإعادة فتحها ثم reconcile؛ حفظ المفتاح الأصلي، عدم تخزين narrative،
عدم replay، التعامل مع unknown/expired/erased/denied ورد الجلسة المتأخر.
منصة المفاتيح في اختبار المضيف وهمية؛ إعادة فتح القاعدة ليست قتل عملية فعليًا.

**DEVICE-VALIDATED RECOVERY:** لا دليل أجهزة جديد في F6-P. دليل iOS Simulator
المحدود من F6-N لم يُعد تشغيله في هذه الدفعة، ولا يثبت file protection على
هاتف فعلي. اختبارات Android runtime غير منفذة. اختبار الهواتف الفعلية DEFERRED
بقرار عمرو. لا تثبيت SDK أو أدوات privileged.

**PRODUCTION-ACTIVATED RECOVERY:** **DISABLED / NOT APPROVED**. لم نربط journal
بمسارات mutation الفعلية أو نغير native configuration أو نتجاوز الحماية.

الحدود المتبقية:

1. قارئات metadata-only مخصصة لبقية المجالات، ومنها adherence والمراسلة والخطط
   والمنح والمراجعات وAgent، **NOT STARTED في هذه الدفعة**؛ منطق in-session
   الموجود لا يساوي استرجاعًا مشفرًا شاملاً بعد restart.
2. notes/reviews القديمة تستخدم correlation محليًا؛ تبني الإيصالات keyed الموجودة
   بالـBackend هو عمل Flutter متبقٍ، وليس API مفقودة.
3. تقويم الروتين CAS-only: بعد رد مفقود تبقى النية الأصلية ومراجعتها؛ ارتفاع revision
   مؤكد من السيرفر يمنع CAS القديم، لكنه لا يثبت هوية الفائز ولا ينشئ receipt.
4. انتهاء التفويض/401 يحتفظ بالهوية الدنيا لنفس الحساب. explicit logout/init/delete
   يبقى مسحًا مقصودًا لذاكرة الجلسة وفق الدورة السابقة. إغلاق التطبيق لا يحفظ
   quarantine الحالي طالما journal غير مفعل؛ لا ندّعي durable recovery للمستخدم.
5. unknown لا يثبت الفشل ولا يبرر key بديلًا؛ لا exactly-once أو replay تلقائي.

## الفحوصات

البداية: `flutter pub get` نجح، `flutter analyze` بلا ملاحظات، **2021 اختبارًا**.
كل دفعة أعادت التحليل وكل اختبارات Flutter، مع focused tests مناسبة:

| الدفعة | المجموعة الكاملة | الجديد |
|---|---:|---:|
| تنقل المريض والثقة |2031|10|
| تاريخ الروتين والتقويم |2055|24|
| سياق الطبيب والخصوصية |2060|5|
| استرجاع الروتين والتجارب |2081|21|
| إشعارات الخطط وتجربة المتابعة |2087|6|
| توسيع الرحلات المترابطة |2087|توسيع4 رحلات الطبيب القائمة دون تضخيم العدد|

**النتيجة النهائية:2087 ناجحًا، +66 عن البداية؛ analyze بلا ملاحظات؛ diff --check نظيف.**
الاختبارات تغطي ردودًا مفقودة، scope/DTO غير متطابق، expiry/401/403،
unknown/expired/erased، تبديل الحساب/المريض، ردودًا متأخرة، CAS، paging،
layout320px200%، themes وتقليل الحركة. اختبارات timeout/offline/5xx
الموجودة والمضافة للروتين والطبيب بقيت في المجموعة الكاملة.

السجلات المحلية لهذه الجلسة:
`/tmp/dermaire-p-baseline-test.log`،
`/tmp/dermaire-p1-full-final.log`، `/tmp/dermaire-p2-full.log`،
`/tmp/dermaire-p3-full-final.log`، `/tmp/dermaire-p4-full-final.log`،
`/tmp/dermaire-p5-full-final.log`، `/tmp/dermaire-p6-full.log`،
`/tmp/dermaire-p6-analyze.log`.
هذه fake-HTTP/widget/host tests وليست خدمات حقيقية أو قياس أمان جهاز.

## احتياجات حسام المؤكدة

آخر تغيير backend ما زال `8ad2ceafced5b1f06ade5a082d4939503d31c687`.
أعدنا مراجعة agent_platform وnotifications وclinical_plans وخدماتها، و
configuration_attempts وmodel_providers. التفاصيل والمسار/الأثر/القبول/الأولوية
في `FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md`:

- P0: fencing/terminal rejection أو in-flight semantics إن أُريد فتح replacement آمن.
- P1: اكتشاف Agent sessions بحدود login/TTL/revocation واضحة.
- P1: pagination لطلبات الطبيب وربط صريح بمريض مصرح به.
- P1: thread target موثوق لإشعارات الرسائل.
- P1 إذا لزم ترتيب عابر للأجهزة: version/CAS لحالة read/unread.
- BLOCKED external: مزود Agent حقيقي، نموذج مقارنة موثق ونقل صور آمن، وPush
  فعلي وإثبات delivery على الأجهزة. لم نغيّر أي provider أو Azure resource.

التاريخ الثابت للخطط بما فيه evaluation history، والتقويم وتاريخ الروتين،
وتسجيل أجهزة الإشعارات، والإيصالات الاختيارية keyed للطبيب موجودة بالفعل؛
لا نطلب إعادة إنشائها. لا تُرسل رسالة لحسام تلقائيًا؛ التقرير هو handoff قابل للتنفيذ.

## ما بقي والخطوات التالية

F6 ككل **PARTIAL**. الخطوة البرمجية التالية: ترقية note/review في Flutter
إلى keyed attempts الحقيقية مع ربط المنحة الأصلية، ثم قارئات المجالات المتبقية
وcurrent-state proof المخصص لكل مجال، وتوسيع الرحلات الموحدة تدريجيًا.
لا تُفعل persistence أثناء ذلك؛ التفعيل يحتاج قرار rollout منفصلًا وبعد
التحقق من الأجهزة والحماية، وunknown/fencing semantics واضحة.
تحسينات المنتج الشاملة ودمج كل19/12 خطوة في رحلتين كاملتين ما زالا PARTIAL؛
لا يُعتبر تأجيل الأجهزة مبررًا لإسقاط العمل البرمجي المتبقي.

## الملفات المعدلة في هذه الموجة

كل اسم أدناه نسبة إلى جذر `/Users/amrabdallah/Dermaire-Project`:

```text
app/docs/FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md
app/docs/FLUTTER_F6_P_EXECUTION.md
app/docs/FLUTTER_IMPLEMENTATION_STATUS.md
app/lib/app_shell.dart
app/lib/dermaire_state.dart
app/lib/doctor/doctor_clinical_controller.dart
app/lib/doctor/doctor_clinical_ui.dart
app/lib/doctor/doctor_context_page.dart
app/lib/doctor_portal.dart
app/lib/home/patient_home.dart
app/lib/integration/configuration_receipt.dart
app/lib/messaging/messaging_ui.dart
app/lib/navigation/patient_care_actions.dart
app/lib/navigation/patient_navigation.dart
app/lib/notifications/inbox_ui.dart
app/lib/observations/observation_ui.dart
app/lib/plans/plan_journey_summary.dart
app/lib/plans/plan_ui.dart
app/lib/recovery/configuration_receipt_reader.dart
app/lib/recovery/recovery_ui.dart
app/lib/routine/routine_evidence.dart
app/lib/routine/routine_evidence_controller.dart
app/lib/routine/routine_evidence_ui.dart
app/lib/routine/routine_ui.dart
app/lib/services/api_service.dart
app/test/home_authority_test.dart
app/test/support/connected_care_workflow.dart
app/test/wave_legacy_identity_lifecycle_test.dart
app/test/wave_p_configuration_recovery_test.dart
app/test/wave_p_doctor_context_test.dart
app/test/wave_p_inbox_plan_workflow_test.dart
app/test/wave_p_patient_navigation_test.dart
app/test/wave_p_routine_evidence_test.dart
app/docs/FLUTTER_F6_P_FINAL_REPORT_AR.md
```
