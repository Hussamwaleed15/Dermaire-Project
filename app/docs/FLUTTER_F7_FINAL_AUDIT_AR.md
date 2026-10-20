# F7 — جرد القدرات وأدلة الإغلاق

البداية2026-10-20: main نظيف، SHA3ec0b03e92c23e177ded80ca48eba24bfb95eeb7،
fetch يطابقه. pub get ناجح؛ analyze clean؛2224 اختبار baseline ناجحًا.
Backend لم يتغير منذ8ad2cea؛ طلب Backend السابق توقف قبل أي تعديل.
نطاق هذه الموجة Flutter فقط، لا native/Tester/live services.

## أبعاد الإثبات المستقلة

I=تنفيذ بالمصدر؛ F=اختبارات fake HTTP/host ذات صلة ضمن المجموعة الكاملة.
B=Backend حي؛ S=Simulator لهذه الوظيفة؛ D=جهاز فعلي؛ P=اعتماد إنتاج.
«لا دليل» لا يعني أن وظيفة لم تُنفذ؛ يعني أننا لا ندعي تأهيل ذلك البعد.

| القدرة / المصدر | I | F | B | S | D | P | المتبقي المصنف |
|---|---|---|---|---|---|---|---|
| Auth/onboarding/safety: services/api_service,entry,account | نعم | نعم | لا دليل | لا دليل لكل auth | مؤجل | لا اعتماد جديد | DEVICE VALIDATION، PRODUCTION QUALIFICATION |
| Profile/Home/observations: account,home,observations | نعم | نعم | لا دليل | لا دليل شامل | مؤجل | لا اعتماد جديد | DEVICE VALIDATION؛ ربط completion بسيرفر فقط |
| Guided camera/private images: capture | نعم | نعم | لا دليل | سابق محدود، لا تأهيل كاميرا شامل | مؤجل | لا اعتماد جديد | DEVICE VALIDATION، PRODUCTION QUALIFICATION |
| Products/routine/adherence: products,routine | نعم | نعم | لا دليل | لا دليل شامل | مؤجل | لا اعتماد جديد | DEVICE VALIDATION؛ original recovery لا replacement آلي |
| Experiments/history/PSM: experiments,psm,routine evidence | نعم | نعم | لا دليل | لا دليل شامل | مؤجل | لا اعتماد جديد | BACKEND DEPENDENCY للنموذج الفعلي منفصل عن evidence الحتمي |
| Grants/snapshot: doctor,clinical | نعم | نعم | لا دليل | لا دليل شامل | مؤجل | لا اعتماد جديد | DEVICE VALIDATION؛ VIEW≠EXPORT |
| Notes/reviews: doctor_clinical_controller | نعم keyed | نعم | لا دليل | لا دليل شامل | مؤجل | لا اعتماد جديد | FLUTTER FIX: أصل grant عند resume؛ BACKEND DEPENDENCY: atomic أول POST |
| Messages/plans: messaging,plans | نعم | نعم | لا دليل | سابق smoke محدود | مؤجل | لا اعتماد جديد | FLUTTER FIX: تثبيت أصل سياق الصفحة؛ تحديث القائمة موجود ويُختبر |
| Comparison/history: plans/plan_evaluation | lifecycle نعم | نعم | لا دليل | سابق محدود | مؤجل | لا اعتماد جديد | EXTERNAL AI DEPENDENCY؛ BACKEND DEPENDENCY لإيصال cancel مستقل |
| Inbox/preferences/reminders: notifications | نعم | نعم | لا دليل | سابق smoke محدود | مؤجل | لا اعتماد جديد | BACKEND DEPENDENCY: thread target/CAS؛ EXTERNAL PUSH DEPENDENCY |
| Agent consent/requests: agent | broker نعم، inference unavailable | نعم | لا دليل | لا دليل شامل | مؤجل | لا اعتماد جديد | BACKEND DEPENDENCY: discovery/paging/target/original proof؛ EXTERNAL AI |
| Receipts/recovery: recovery | memory/readers نعم؛ disk isolated | نعم | لا دليل | F6-N محدود فقط | مؤجل | DISABLED | FLUTTER FIX: factory مشتركة للقارئات وcomposition معزول؛ DEVICE/PRODUCTION gates |
| Logout/switch/delete: API/controllers | نعم | نعم | لا دليل | سابق محدود | مؤجل | لا اعتماد جديد | DEVICE VALIDATION؛ PHI cleanup≠physical flash erasure |
| Navigation/accessibility: themes/UI | نعم | نعم | غير منطبق | سابق محدود | مؤجل | لا اعتماد جديد | حماية السياق المثبتة؛ التنقل الحالي محفوظ؛ لا redesign |

## خطة التنفيذ المحددة

1. F7-B/F: تثبيت original grant في صفحة السياق وclinical controller؛ replacement
   لا يعيد فتح صفحة قديمة. same-grant refresh يبقى ممكنًا. اختبارات controller/UI،
   late-response/replacement وبدء صفحة جديدة بصلاحيتها الحالية. لا claim atomic POST.
2. F7-E/F/G: التحقق باختبارات actual widgets من تحديث القوائم بعد الرجوع.
   الفحص الأعمق أثبت وجود refresh في DoctorViewLifecycle حتى للمريض؛
   طبقة Navigator تمنع الضغطة الثانية بالفعل. لا تعديل زائد لهذين السلوكين.
3. F7-C/D: استخراج اختيار القارئات الفعلية من UI إلى factory قابلة للحقن صراحة
   في composition معزول؛ اختبارات SQLCipher restart + domain readers، لا تفعيل حي.
4. F7-H/I: focused/analyze/full/diff/scope/fetch لكل دفعة؛ تسليم backend دقيق.

القارئات الحالية تغطي كل العقود ذات receipt مستقل المتاحة. Agent action-attempt
يرجع CURRENT action؛ notification/current CAS وcalendar CAS وevaluation DELETE
ليست original receipts. لا endpoint جديد أو universal status مخترع. unknown لا
يعني rejected/in_flight ولا إذن replay. مزودو inference/Push ما زالوا unavailable.

## F7-B/F نتيجة الدفعة الأولى

تثبيت grant مرة واحدة في DoctorContextPage وDoctorClinicalController. إعادة
التحقق بنفس المنحة لا تكسر الاستخدام؛ المنحة البديلة لا تعيد binding الصفحة
القديمة. شاشة notes/reviews تزيل المسودات وتعرض تعذر الوصول عند اختلاف الأصل.
فتح صفحة جديدة صراحة يمكنه استخدام المنحة الجديدة بعد تحقق السيرفر.
8 اختبارات جديدة، focused80/full2232/analyze clean. الرد السريري المتأخر يحتفظ
بالهوية الدنيا الأصلية ولا يعيد payload أو private receipt إلى الصفحة.
ضمان أول كتابة ذريًا ما زال BACKEND DEPENDENCY؛ لا header مخترع في هذه الدفعة.

## F7-C/D/E/F نتيجة الدفعة الثانية

RecoveryReaderCatalog أصبح مصدر اختيار القارئات الحالي في واجهة memory review
وفي composition المعزول المحقون صراحة. يثبت owner/role/generation وسياسة السلامة،
ويرفض foreign identity/جلسة قديمة والعقود غير المدعومة دون HTTP. لا ينشئ storage
أو sender أو rollout flag ولا يُفعّل journal في الإنتاج.

14 اختبارًا جديدًا: real SQLCipher host + منصة مفاتيح وهمية + fake HTTP للمراسلة
والخطط في الدورين. COMMIT UNCONFIRMED يسبق الإرسال الصناعي؛ فشل إقرار الحماية
يمنع الإرسال حتى لو حُفظ PREPARED. controlled reopen يحفظ المفتاح؛ unknown يظل
unresolved؛ receipt الأصلي revision2 مستقل عن current revision3؛ رفض الصلاحية
permissionDenied؛ logout/cross-account يمنعان القراءة والاختيار. لا replay.
اختبارات corruption/missing-key/plaintext والحدود الأصلية محفوظة ضمن المجموعة.

8 رحلات إضافية في الثيمين و320px200% وتقليل الحركة تثبت actual list -> message/send
أو plan/acknowledge/reschedule -> back -> current list readback لكلا الدورين.
ليس ذلك تنفيذ refresh جديدًا؛ هذه الوظيفة كانت موجودة. محاكاة ضغط ثانٍ قبل frame
أثبتت أن Navigator يمنع وصوله؛ لم نغيّر التنقل أو نُبقِ hit-test warnings في suite.

focused65/full2254/analyze clean. +30 عن baseline2224 للموجة كلها.
