# F7 Flutter — التقرير النهائي للتنفيذ والإغلاق البرمجي

2026-10-20. **الحالة الإجمالية PARTIAL**؛ تحسنت سلامة Flutter وتكامل الاسترداد
المعزول، ولا يُعد ذلك تأهيلًا كاملًا للتطبيق أو Backend أو الأجهزة أو الإنتاج.

## Git والنطاق

- البداية: `3ec0b03e92c23e177ded80ca48eba24bfb95eeb7`، main نظيف، origin fetch/push الرسمي مطابق، fetch أكد SHA.
- آخر تنفيذ اختُبر ورفع: `2314ae2da97806b3d21cefab791d9b2d3df12ef3`؛ fetch اللاحق أكد تطابق 2314ae2da97806b3d21cefab791d9b2d3df12ef3 وorigin/main.
- commit توثيق أخير يتبع هذا checkpoint لإضافة هذا التقرير والتسليم والدليل؛
  SHA النهائي لذلك commit والتحقق البعيد النهائي في رسالة التسليم. لا نضع
  SHA ذاتيًا مخترعًا في ملف يحتويه نفس commit.
- آخر تغيير Backend: `8ad2ceafced5b1f06ade5a082d4939503d31c687`، دون ضمان
  ذري جديد. طلب Backend السابق توقف قبل أي تعديل؛ هذه الموجة Flutter فقط.
- جميع التغييرات في app/lib وapp/test وapp/docs. لا Backend أو Tester أو
  native Android/iOS أو Azure أو DB أو Production/Staging/provider edits.
- كل دفعة: focused، analyze، full suite، diff-check، مراجعة حساسة ونطاق،
  fetch للفرع المشترك، commit مستقل وpush عادي. لا force أو reset أو إعادة تاريخ.
- واجه نقل Git تعليقًا مؤقتًا؛ أُلغي الجلب المعلق وأُعيد بنجاح باستخدام
  HTTP/1.1 لذلك الأمر فقط، دون تغيير إعداد دائم أو تخطي حماية الفرع.

الدفعتان البرمجيتان:

```text
9dcab2003af4858cef1921c01a0dedc81ed1323c fix(flutter): bind clinical pages to their original verified grant
2314ae2da97806b3d21cefab791d9b2d3df12ef3 refactor(flutter): share scoped receipt readers with isolated journal recovery
```

## المنفذ للمستخدم وللاسترداد

**أصل صلاحية الطبيب:** DoctorContextPage وDoctorClinicalController يثبتان grant
الأصلي بدل استبداله ضمن الصفحة القديمة عند refresh. المنحة البديلة لا تعيد
إظهار المحتوى أو تفعيل الكتابة في editor قديم. الشاشة تمسح المسودات وتعرض انتهاء
الوصول عند اختلاف السياق؛ استجابة قديمة لا تعيد raw receipt أو narrative.
هوية العملية الدنيا تبقى للأصل وفق lifecycle. إعادة قراءة نفس المنحة تعمل،
ويمكن فتح صفحة جديدة صراحة لصلاحية جديدة مؤكدة من السيرفر.

هذا حارس Flutter مستقل. **لا يحل atomic first-write authorization**. POST
notes/reviews لا يملك precondition للـoriginal grant بعد؛ GET ثم POST ليس معاملة
ذرية، ولم نخترع header أو field. keyed original receipt وpayload/sequence CAS
والفصل بين القرار الحالي والإيصال التاريخي محفوظون من F6-Q.

**القارئات والتركيب المعزول:** استخراج RecoveryReaderCatalog من اختيار القارئ
داخل UI، ليصبح الاختيار نفسه متاحًا للواجهة الحالية ولـdependency injection
الصريح في اختبارات SecureRecoverySession. يثبت الحساب والدور وgeneration
وسياسة السلامة، ويرفض foreign/stale/unsupported identities قبل طلب HTTP.
لا ينشئ قاعدة أو sender ولا يحتوي flag لتفعيل مسارات الإنتاج. قارئات المجالات
المتخصصة كما هي؛ لم نختلق universal receipt أو دعمًا لـAgent/notification غير موجود.

**رحلات الرعاية:** ثماني رحلات widget إضافية للثيمين والدورين و320px200% وتقليل
الحركة: list → conversation/send أو plan/acknowledge/reschedule → back → latest
list. أثبتت أن التحديث موجود أصلًا في DoctorViewLifecycle. الاختبار الأولي أظهر
أن طبقة Navigator تمنع الضغطة الثانية قبل frame أيضًا؛ لم نصنع إصلاحًا زائدًا
لهذين السلوكين ولم نُبقِ تحذيرات hit-test في الاختبارات النهائية. لا redesign
أو تغيير ألوان/لغة/شعار أو زر الكاميرا الأوسط.

## حالات F7 ومعيار اكتمال كل منها

| المسار | الحالة | النتيجة والحد |
|---|---|---|
| A جرد القدرات | DONE للمصدر / PARTIAL للتأهيل | مصفوفة مستقلة لكل feature لأبعاد implemented/fake HTTP/backend/simulator/device/production في تقرير audit |
| B notes/reviews | DONE للحارس المستقل / BLOCKED للذرية الخلفية | fixed original grant عبر refresh والرد المتأخر؛ لا تعديل server أو claim TOCTOU solved |
| C readers | DONE لكل العقود المتاحة / BLOCKED للأصول الغائبة | products/configuration/adherence/messages/clinical/grants/plans/comparison محفوظة ومشتركة؛ لا reader مزيف للـAgent/current CAS |
| D journal software | DONE للتركيب المعزول المحدد / PARTIAL للتأهيل | SQLCipher وreal reader composition قبل/بعد controlled reopen؛ لا process-death جديد ولا device security proof |
| E رحلة المريض | DONE للتحقق المحدد / PARTIAL للرحلة الشاملة | latest list بعد إرسال/قبول خطة، مع رحلات F6 السابقة وسحب الموافقات على المحاكي؛ ليس مسارًا واحدًا لكل وظائف المنتج |
| F رحلة الطبيب | DONE للإصلاحات والاختبارات المحددة / PARTIAL للشامل | original grant ثابت، late response، صفحة جديدة، plan reschedule/message/list؛ ذرية الأصل Backend-blocked |
| G UX/accessibility | DONE للمجال المحدد / PARTIAL لتأهيل المنتج | صفحة قديمة محجوبة دون PHI، ثيمان وsmall screen/large text/reduced motion، الهوية الحالية محفوظة |
| H regression | DONE host + smoke محدد / PARTIAL للأجهزة وE2E |2254 host tests/analyze clean و1 iOS smoke؛ لا Backend حي أو هواتف فعلية |
| I Git/handoff | DONE للشيفرة والتسليم الموثق | دفعتان مرفوعتان ومزامنة مؤكدة، توثيق إغلاق لاحق؛ قائمة عقود حسام source-grounded |

لم يظهر بعد الجرد عطل Flutter مستقل آخر مثبت في النطاق المتبقي؛ الوظائف التي
طلبت قارئًا إضافيًا بلا عقد أصل مستقل، أو ضمانًا ذريًا في السيرفر، لا تُحل بإضافة
اختبارات أو replay محلي. لا ادعاء خلو التطبيق كله من العيوب أو اكتمال المنتج.

## الاختبارات والأدلة

| النقطة | Focused | Full Flutter | analyze |
|---|---:|---:|---|
| baseline مع pub get | — |2224|clean|
| original context |80|2232|clean|
| scoped catalog + journal + journeys |65|2254|clean|

الجديد30 حالة:8 original-context،14 journal-domain،8 care-navigation. Focused
يتضمن حالات حالية ذات صلة وليس عدد الحالات الجديدة. لم نضعف اختبارات موجودة.

اختبارات أصل الطبيب: note/review، منحة بديلة قبل الكتابة وأثناء رد معلق، عدم
عودة المسودات/receipt، عدم إرسال POST آخر، minimum identity retains original
access، same-grant refresh، new-page explicit binding، كلا الثيمين والنص الكبير.
الاختبارات الحالية لتعارض payload/key/CAS/سياسة السلامة والحساب وانتهاء الجلسة
وprivate-current review precedence بقيت ضمن المجموعة الكاملة.

اختبارات journal الجديدة على SQLCipher حقيقي وJournalPlatform وهمي:

- PREPARED ثم UNCONFIRMED commit قبل الإرسال الصناعي بالمفتاح الأصلي.
- فشل إقرار الحماية يمنع الإرسال حتى إذا بقي PREPARED على القرص؛ لا fallback.
- controlled close/reopen يستعيد نفس الحساب والدور والمفتاح دون body/narrative.
- unknown/persistence-failure تظلان unresolved؛ revoked/closed permissionDenied.
- plan original revision2 مستقل عن current revision3 الملغى، فتكون reviewRequired.
- cross-account journal read مرفوض؛ فقد policy أو logout يمنع اختيار القارئ أو
  قراءة الجلسة القديمة؛ لا replay أو مفتاح بديل.

الاختبارات الأصلية للمفتاح الغائب/الفاسد وciphertext/schema فساد ورفض plaintext
والـCAS/cleanup محفوظة. منصة مفاتيح الاختبار وهمية؛ لا Keystore/Keychain
hardware qualification. controlled reopen ليس قتل عملية على هاتف.

الأدلة المحلية: `/tmp/dermaire-f7-baseline-test.log`،
`/tmp/dermaire-f7-b-focused.log`، `/tmp/dermaire-f7-b-full.log`،
`/tmp/dermaire-f7-d-focused.log`، `/tmp/dermaire-f7-d-analyze.log`،
`/tmp/dermaire-f7-d-full.log`، `/tmp/dermaire-f7-ios-smoke.log`.
ملخص محفوظ بلا أسرار: [F7_HOST_SIMULATOR_EVIDENCE.json](validation/F7_HOST_SIMULATOR_EVIDENCE.json).

## دليل المحاكي وحدوده

المحاكي الموجود iPhone17 / iOS26.0 / UDID
DB96C794-96EA-4BB6-BDB3-301F8F385FB9 شُغّل من Shutdown.
`integration_test/withdrawal_smoke_test.dart` نجح: **1 test**، Xcode build27.6s.
المسار الصناعي يغطي بوابة السلامة وسحب الموافقات والخطة/إلغاء طلب التقييم ثم
logout/account switch. كل HTTP معترض بـMockClient ويشترط flutter-tests.invalid؛
لا OAuth أو بيانات حقيقية أو Production/Staging أو تعديل native/SDK جديد.
بعد التنظيف الداخلي أُعيد المحاكي إلى Shutdown، وتحقق عدم وجود جهاز booted.

هذا دليل حديث للمسار المذكور فقط، لا تصوير فعلي أو حماية ملفات جهاز أو
موثوقية مفاتيح hardware أو Backend E2E أو نموذج AI أو Push. لم نجمع screenshot
أو فيديو أو ندّعِ تأهيل كل واجهات التطبيق على المحاكي.

## فصل الأدلة والاعتماد

- **IMPLEMENTED:** الحواجز والقارئات والواجهات الحالية وفق مصفوفة audit.
- **TESTED WITH FAKE HTTP/HOST:**2254 اختبارًا، وSQLCipher metadata في namespaces
  مؤقتة؛ لا narrative محفوظ في journal.
- **TESTED AGAINST BACKEND:** لا دليل جديد، لم تُرسل طلبات Backend حية.
- **SIMULATOR TESTED:** smoke1 المحدد أعلاه فقط؛ تفاصيل F6-N السابقة تبقى محدودة.
- **PHYSICAL DEVICE TESTED:** مؤجل بتوجيه عمرو؛ لا دليل جديد.
- **PRODUCTION APPROVED:** لا اعتماد أو نشر جديد. journal يظل **DISABLED / NOT
  APPROVED للعمليات الحية**؛ لا native change أو protection bypass أو automatic replay.

## حسام والمتبقي القابل للتنفيذ

[التسليم الدقيق](FLUTTER_F7_HUSSAM_HANDOFF.md) يميز العقد الحقيقي عن المقترح،
مع endpoints/headers/response shapes/errors وأثر Flutter ومعايير PostgreSQL.
لا رسالة تلقائية لحسام، ولا تعديل Backend أو migrations في موجة Flutter.

| التصنيف | الأولوية والحالة | العمل التالي الجاهز |
|---|---|---|
| BACKEND DEPENDENCY |P0 BLOCKED replacement|durable reservation/terminal rejection/fencing؛ unknown ليس rejection أو إذن إعادة إرسال|
| BACKEND DEPENDENCY |P1 BLOCKED atomic first POST|precondition للمنحة الأصلية ضمن transaction كتابة note/review؛ قرار توافق legacy/hardened مطلوب من Backend|
| BACKEND DEPENDENCY |P1 PARTIAL Agent|discovery/current lookup semantics، pagination بدل حد100، authorized patient reference، immutable original confirmation/submit proof|
| BACKEND DEPENDENCY |P1 PARTIAL notification|trusted thread target/resolver، cross-device version/CAS عند طلب ترتيب عالمي؛ لا طلب إعادة إنشاء prefs/reminders/device registration|
| BACKEND DEPENDENCY |P2 conditional|original evaluation DELETE cancellation proof عند الحاجة لاسترداد مستقل؛ calendar CAS لا يصبح receipt|
| EXTERNAL AI/PUSH |BLOCKED|مزود Agent حقيقي ونموذج مقارنة موثق ونقل صور خاص وتحقق طبي وPush حقيقي ودليل delivery|
| DEVICE VALIDATION |DEFERRED|iOS Data Protection/Keychain وAndroid Keystore/backup/crash/full-disk/restore؛ لا تثبيت أدوات أو تعديل native في هذه المهمة|
| PRODUCTION QUALIFICATION |NOT APPROVED|بعد التأهيل وموافقة منفصلة فقط يمكن بحث تركيب journal/startup/logout/domain rollout؛ لا تفعيل تلقائي|

PostgreSQL: lock-order revocation/write، duplicate keys، concurrent review CAS،
original receipt بعد lost response، policy/account deletion، ordering للـnotification
ومنع resurrection بالـgrant البديل. هذه متطلبات تحقق لدى حسام، **لم تُشغل هنا**.
بعد نشر العقد الصحيح يضيف عمرو mock contracts/المدخل الفعلي/capability gating
والقارئات اللازمة ثم يعيد فحوصات Flutter؛ لا يرسل المقترح قبل وجوده في السيرفر.

## الملفات المعدلة

- `app/docs/FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md`
- `app/docs/FLUTTER_F7_FINAL_AUDIT_AR.md`
- `app/docs/FLUTTER_F7_FINAL_EXECUTION_REPORT_AR.md`
- `app/docs/FLUTTER_F7_HUSSAM_HANDOFF.md`
- `app/docs/FLUTTER_IMPLEMENTATION_STATUS.md`
- `app/docs/validation/F7_HOST_SIMULATOR_EVIDENCE.json`
- `app/lib/doctor/doctor_clinical_controller.dart`
- `app/lib/doctor/doctor_clinical_ui.dart`
- `app/lib/doctor/doctor_context_page.dart`
- `app/lib/recovery/recovery_reader_catalog.dart`
- `app/lib/recovery/recovery_ui.dart`
- `app/test/wave_f7_care_navigation_test.dart`
- `app/test/wave_f7_journal_domains_test.dart`
- `app/test/wave_f7_original_context_test.dart`

العدد14، كلها داخل النطاق المصرح. لا تغيير لمكتبات Flutter أو إعدادات المنصات
أو البرودكشن. تقرير الإغلاق وتحديثا الحالة وتسليم حسام ودليل الاختبارات ضمن القائمة.
