# تقرير Flutter F6-Q — التنفيذ والتحقق والتسليم

تاريخ الإغلاق البرمجي: 2026-10-20. المالك: عمرو؛ Backend/Azure/DB/AI: حسام.

## النتيجة ونطاق الإثبات

تم تنفيذ ورفع ست مراحل برمجية مستقلة على `main`. الاختبارات زادت من **2087**
إلى **2224**، بإضافة **137** حالة انحدار مفيدة، والتحليل بدون مشاكل. الموجة
قدمت ربطًا فعليًا لمحاولات الملاحظات والمراجعات السريرية، قارئات استرداد متخصصة،
تجربة تحقق صريحة، وإصلاحات تنقل وعزل بيانات المريض. **F6 والتطبيق ككل PARTIAL**؛
لم نختبر Backend حيًا أو أجهزة فعلية، ولم تُفعّل كتابة journal في مسارات الإنتاج.

- البداية المتحققة: `1df9822adb9690f2146fc754258f724a1b3b0c19`، فرع main نظيف ومتطابق مع origin/main.
- آخر SHA تنفيذ تم اختباره ورفعه: `ed83523c1c54a7674cd0e84e42009434bedc5a16`.
- تحقق `git ls-remote origin refs/heads/main` أعاد نفس SHA التنفيذ بعد آخر push؛
  شجرة العمل كانت نظيفة. يتبع ذلك commit توثيق فقط لهذا التقرير وتحديث الحالة
  والتسليم. SHA إغلاق التوثيق وحالة remote النهائية يسجلان في رسالة التسليم؛
  SHA التنفيذ أعلاه يثبت الشيفرة التي اجتازت الفحوصات.
- المصدر الخلفي الذي أعيد فحصه: `8ad2ceafced5b1f06ade5a082d4939503d31c687`.
- origin fetch/push: `https://github.com/Hussamwaleed15/Dermaire-Project.git`.
- لا force push ولا إعادة كتابة تاريخ مشترك ولا إلغاء تغييرات زميل.

## سجل مراحل التنفيذ

```text
6969f4c3b6f9821e2721f44f6c32ac6acb77cf7b feat(flutter): reconcile keyed clinical note and review attempts
9d3df97c33c238c85911809de0f9602ad085d69c feat(flutter): review clinical and adherence recovery metadata safely
ee1f8a8691c5393556a1ee7ad288e3169f049202 feat(flutter): verify original care message and clinical plan receipts
2db8a22efa6f343e98709c4df8249162e5ece8de feat(flutter): verify consent recovery without restoring bearer invitations
3989563f9fab655b5611fbfb89fa7a71c6ad9c94 feat(flutter): make uncertain operation verification actionable
ed83523c1c54a7674cd0e84e42009434bedc5a16 fix(flutter): protect nested patient routes and refresh Home on return
```

| المرحلة | Focused | Full Flutter | التحليل |
|---|---:|---:|---|
| baseline: pub get + analyze + test | — | 2087 | clean |
| Q1 clinical keyed receipts | 131 | 2124 | clean |
| Q2a clinical/adherence metadata | 118 | 2150 | clean |
| Q2b messaging/plans/comparison | 123 | 2178 | clean |
| Q2c consent/claim | 118 | 2190 | clean |
| Q3 uncertainty/explicit finish | 85 | 2194 | clean |
| Q4/Q5/Q6 navigation/privacy | 133 | 2224 | clean |

عدد Focused يتضمن اختبارات حالية ذات صلة، وليس عدد الحالات الجديدة في كل مرحلة.
أُجري diff-check وفحص النطاق والفرع المشترك قبل كل commit برمجي وpush طبيعي.
سجلات آخر فحص: `/tmp/dermaire-q4-focused.log`،
`/tmp/dermaire-q4-full.log`، `/tmp/dermaire-q4-analyze.log`.
Flutter 3.44.8 / Dart 3.12.2. لا ترقية SDK أو اعتماد جديد في Q.

## مصفوفة Q0–Q8 الحالية

| المسار | الحالة | ما تم وإلى أين يمتد الإثبات |
|---|---|---|
| Q0 | DONE | مصدر Flutter وعقود Backend المسجلة، baseline وremote ونطاق العمل |
| Q1 | DONE ضمن عقد Flutter الحالي | ربط حقيقي للملاحظات والمراجعات بالمفتاح والحمولة الأصلية والإيصال؛ فجوة atomic original-grant لأول كتابة منفصلة لحسام |
| Q2 | PARTIAL | كل قارئات المجالات المطلوبة ذات عقد أصل مستقل متاح منفذة؛ Agent/notifications/calendar/evaluation DELETE لا تملك نفس عقد الإثبات، فلا قارئ وهمي |
| Q3 | DONE ضمن تجربة التحقق | حالة لكل عملية وتوقيت قراءة وخطوة تالية وإنهاء صريح بعد إثبات أصلي وحالي جديدين؛ لا replay |
| Q4 | PARTIAL للخريطة الكاملة | إصلاحات Home والرحلات المتصلة المختبرة مكتملة؛ لا ادعاء رحلة واحدة تشمل كل مجالات المنتج أو Backend E2E |
| Q5 | PARTIAL للخريطة الكاملة | عزل nested routes وإنشاء/فتح/إعادة جدولة خطة وتسجيل review مختبرة؛ لا ادعاء مراجعة طبية فعلية أو inference |
| Q6 | PARTIAL | حواجز جلسة/سياق وصلاحية وردود متأخرة واختبارات إخفاء/إزالة المحتوى؛ ليس تدقيق أمن شاملًا أو اكتشافًا لحظيًا لسحب بعيد لم يُقرأ بعد |
| Q7 | DONE للإصلاحات المحددة / PARTIAL للمنتج | تحقق صادق وتنقل/refresh مفيد مع الهوية الحالية والتكبير وتقليل الحركة؛ لا إعادة تصميم |
| Q8 | DONE للفحص البرمجي / PARTIAL للأجهزة وE2E | جميع الاختبارات والتحليل والتسليم؛ الاختبارات الحية والأجهزة مؤجلة |

## الملاحظات والمراجعات السريرية

`doctorResource` يثبت المفتاح والحمولة والمسار الحقيقي للمحاولة والمريض والطبيب
والـgrant الأصلي، ويرسل `Idempotency-Key` إلى POST notes/reviews. يحتفظ بالهوية
الأصلية عند فقد الرد، ولا يولد مفتاح بديلًا تلقائيًا. أسماء legacy الداخلية
للتوافق ليست كتابة غير keyed بعد هذا التغيير.

`ClinicalOperationReceipt` يفحص schema/actor/patient/access/operation/resource/
retention وsnapshot الأصلي. المراجعة يجب أن تطابق expected_sequence+1 والحمولة.
`DoctorClinicalController` يقرأ الإيصال الحقيقي والحالة المصرح بها الحالية مستقلين؛
قرار قديم لا يحل محل قرار أحدث. زر Verify original note/review يقرأ فقط.
unknown/expired/erased/contradictory/denied لا تتحول إلى نجاح كاذب.

الاختبارات تشمل الملاحظة والمراجعة الناجحتين، المفتاح المتكرر والحمولة المختلفة،
ردًا مفقودًا بعد commit، قراءة الأصل، قرارًا أحدث، CAS stale، صلاحية مسحوبة،
مريضًا محذوفًا، حسابًا مختلفًا، ردًا متأخرًا، unknown/expired ورفض الوصول.
كل ذلك عبر mocks لعقود فعلية، وليس إثباتًا لتنفيذ Backend أو production.

الحد المتبقي: backend يختار أحدث VIEW grant تحت القفل، وPOST لا يقبل precondition
لـoriginal access على أول كتابة. Flutter يفحص قبل الطلب وبعد الإيصال لكنه لا
يجعل الفاصل بينهما ذريًا. لم نخترع access header أو field. إعادة نفس المفتاح
مع grant بديل مرفوضة أصلًا في السيرفر. المطلوب من حسام إضافة precondition ذري
لأول كتابة فقط، مع الحفاظ على sequence CAS وعدم إنشاء سجل عند تغير grant.

## قارئات الاسترداد وحدود كل مجال

| المجال | التنفيذ | الحدود الصادقة |
|---|---|---|
| المنتجات وروتين/تجربة configuration | القارئات السابقة محفوظة | الأصلي والحالي مستقلان، لا replacement تلقائي |
| adherence | قارئ جديد للعقد الخاص ونُسخة configuration/actor/report | لا استعادة note؛ بحث history محدود 5000 صف مع كشف التداخل، عدم العثور ليس حذفًا أو إذن إعادة إرسال |
| notes/reviews | قارئ جديد لنفس clinical envelope | current review الأحدث يتطلب مراجعة؛ grant بديل لا يحيي السلطة القديمة |
| messaging | قارئ جديد لإيصال رسالة مع thread/actor/sequence، ثم الرسالة الحالية | إعادة فحص المشاركة والـgrant والـconsent، لا تخزين/عرض body من metadata |
| plans/comparison | قارئ جديد للإنشاء وعمليات plan وevaluation/review | plan DTO وjob DTO منفصلان؛ وظيفة ملغاة/مستبدلة لا تعني معالجة حالية أو AI مكتملًا |
| issue/revoke/revoke_all | قارئ GrantAttempt خاص بالمريض | الإيصال لا يعيد صلاحية bearer؛ grant جديد بعد bulk revoke لا يعد مسحوبًا |
| claim | قارئ ClinicalAttempt مع اصل المريض والطبيب والـgrant | hint من الكود مجرد توجيه غير موثوق؛ لا grants من hint ولا استعادة token؛ الكود opaque بلا مسار معروف يبقى ضمن مساره الآمن الحالي |
| Agent | current-state/CAS والمسارات السابقة محفوظة | action-attempt GET يعيد CURRENT action، وليس immutable original confirmation/request؛ BLOCKED لإثبات الأصل المستقل |
| notifications/calendar | current-state/CAS وفق العقد الحالي | لا receipt أصلي مستقل أو ضمان ترتيب عالمي read/unread؛ PARTIAL |
| evaluation cancellation DELETE | current/history وrevision وفق الموجود | لا keyed cancellation receipt؛ BLOCKED لقارئ إثبات أصل مستقل |

المحتوى الخاص يُمسح عند فقد السياق؛ هوية العملية الدنيا وحدها قد تبقى للتحقق.
القارئات لا تعيد تكوين clinical narrative أو message body. الاختبار الذي يعيد
فتح SQLCipher على المضيف يثبت التوافق البرمجي للهوية فقط، وليس hardware security
أو قتل تطبيق على هاتف أو اعتماد production.

## تجربة العمليات غير المؤكدة

تعرض الواجهة unknown/expired/current-record-checked/review-required/
permission-unavailable/verification-unavailable لكل هوية، مع وقت UTC لآخر قراءة
وخطوة تالية واضحة. وقت التحقق ليس وقت إجراء طبي أو تصريحًا طبيًا.

Finish verified receipt review يعيد قراءة الأصل والحالي قبل إزالة هوية الذاكرة
المطابقة. metadata متغيرة، جلسة قديمة، intent نشط، 503 أو رفض أو mismatch تبقي
القفل. لا POST ولا مفتاح جديد ولا تخطي بواسطة تخزين محلي. اختلاف الحالة الحالية
يتطلب مراجعة منفصلة؛ الإيصال القديم لا يغطي الحالة الحديثة. المجالات غير المدعومة
تحصل على تفسير مفيد بدل زر تحقق من endpoint مخترع.

## رحلات المريض والطبيب والخصوصية

- Home يعود لقراءة السيرفر بعد الرجوع من الملاحظة/التاريخ/السلامة/الروتين/السياق؛
  يمنع فتح نفس المسار بالتوازي، ويمنع refresh تابعًا لجلسة انتهت.
- اختبار فعلي Home → Observation → Guided camera disclosure → رجوع → حفظ report
  مؤكد → Home → Routine → رجوع، في كلا الثيمين و320px200% وتقليل الحركة.
  لا تشغيل كاميرا أو صلاحيات هاتف؛ startLiveCamera لم يُضغط.
- report-only يظل report مؤكدًا، دون تحويل Home today_checked_in محليًا إلى true.
  اختبار تبديل الحساب أثناء فتح route يمنع قراءة Home من الجلسة القديمة.
- أصلحنا فجوة Navigator: غلاف قائمة المريض لا يغطي route تفاصيل أُضيفت فوقها.
  الآن المحادثة وتفاصيل الخطة وOpen confirmed plan تحمل نفس connection الأصلية.
- اختبارات تبديل المريض/سحب الصلاحية الملحوظ/الخروج تزيل تفاصيل الرسائل والخطط،
  سواء المحتوى وصل مسبقًا أو بقي GET معلقًا ثم وصل بعد فقد السياق.
- إنشاء خطة ثم فتحها وإعادة جدولتها يتحقق من revision والحالة وCairo11:00/09:00Z
  في snapshot السيرفر الوهمي، ثم تبديل المريض يزيل كل التفاصيل القديمة.
- الرحلات المتصلة الثماني السابقة محفوظة. مسارات الطبيب تضيف review keyed
  بعد note، وتتأكد من sequence1 وتوصية الطبيب مستقلة مع حفظ urgent safety،
  ثم رسائل وخطط وأدلة وسحب صلاحية وخروج وحساب بديل.
- ضوابط VIEW/EXPORT والـconsent/server profile/session الأصلية محفوظة.
  لا PHI أو tokens جديدة في logs، ولا تغيير للاسم/الشعار/الثيم المعتمد.

هذه إصلاحات واختبارات محددة، وليست ضمان اكتمال كل مسار المنتج في سيناريو واحد.
المقارنات تظل مرتبطة بخطة حقيقية ولا pairing عشوائي أو نسب تحسن/تشخيص مختلقة.

## الأجهزة والإنتاج

Implemented: الشيفرة والقارئات والواجهات الموضحة أعلاه.
Tested: Unit/Widget وSQLCipher host metadata bounded؛ fake HTTP يرفض production hosts.
Device-validated: **لا إثبات جديد في Q**؛ لم يُشغّل simulator جديد أو أجهزة فعلية.
Production-approved: **لا تفعيل journal ولا نشر**.

بنية F6-N موجودة لكن journaling في production mutations يبقى DISABLED / NOT APPROVED.
لا native Android/iOS أو Tester أو Backend/Azure/DB/provider edits. لا Google OAuth
حقيقي أو بيانات مرضى أو اختبار production/staging أو تثبيت أدوات/SDK إضافية.
اختبارات أجهزة Android/iPhone والفحص الصارم لحماية الملفات/المفاتيح مؤجلة بتوجيه
عمرو؛ تقرير F6-N السابق لا يتحول تلقائيًا إلى اعتماد نشر في هذه الموجة.

## تسليم حسام والخطوات التالية

التفاصيل مع endpoint/سلوك/عقد مطلوب/أثر/معيار قبول وأولوية في
[FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md](FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md).
لم نرسل رسالة تلقائية لحسام. الأولويات الفعلية:

1. P0 semantics للحجز/in-flight/terminal rejection/fencing قبل أي replacement آمن.
2. P1 original-grant precondition ذري لأول note/review؛ ليس طلب إعادة بناء keyed APIs.
3. P1 Agent discovery/inbox pagination/authorized patient target وimmutable original
   confirmation/request proof عند الحاجة للاسترداد المستقل.
4. P1 authorized notification thread target وCAS لترتيب read/unread عبر الأجهزة.
5. P2 original evaluation-cancellation receipt إن طُلب استرداد مستقل؛ calendar CAS
   يظل مختلفًا عن receipt أصلي.
6. Providers/AI/Push حقيقيون يحتاجون عمل حسام واعتمادًا وفحصًا منفصلًا.

الخطوات التالية: تنفيذ العقود المحددة لدى حسام ثم إضافة Flutter contract tests
وقارئات المجالات المتبقية؛ بعدها توسيع الرحلات المتصلة بناءً على الوظائف المتاحة.
فحص الأجهزة يبقى مسارًا منفصلًا مؤجلًا. تفعيل journal يحتاج موافقة صريحة جديدة
وqualification، ولا يبدأ تلقائيًا لأن الاختبارات البرمجية نجحت.

## الملفات المعدلة في الموجة

- `app/docs/FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md`
- `app/docs/FLUTTER_F6_Q_EXECUTION.md`
- `app/docs/FLUTTER_F6_Q_FINAL_REPORT_AR.md`
- `app/docs/FLUTTER_IMPLEMENTATION_STATUS.md`
- `app/lib/doctor/access_invitation.dart`
- `app/lib/doctor/clinical_operation_receipt.dart`
- `app/lib/doctor/doctor_clinical_controller.dart`
- `app/lib/doctor/doctor_clinical_ui.dart`
- `app/lib/doctor_portal.dart`
- `app/lib/home/patient_home.dart`
- `app/lib/messaging/messaging_ui.dart`
- `app/lib/plans/plan_controller.dart`
- `app/lib/plans/plan_ui.dart`
- `app/lib/recovery/adherence_receipt_reader.dart`
- `app/lib/recovery/clinical_receipt_reader.dart`
- `app/lib/recovery/grant_receipt_reader.dart`
- `app/lib/recovery/message_receipt_reader.dart`
- `app/lib/recovery/plan_receipt_reader.dart`
- `app/lib/recovery/recovery_check.dart`
- `app/lib/recovery/recovery_ui.dart`
- `app/lib/routine/adherence_operation.dart`
- `app/lib/services/api_service.dart`
- `app/test/m6_clinical_reviews_test.dart`
- `app/test/m6_doctor_fixture.dart`
- `app/test/support/connected_care_workflow.dart`
- `app/test/wave_access_test.dart`
- `app/test/wave_q_care_readers_test.dart`
- `app/test/wave_q_clinical_receipt_test.dart`
- `app/test/wave_q_domain_readers_test.dart`
- `app/test/wave_q_grant_readers_test.dart`
- `app/test/wave_q_navigation_privacy_test.dart`
- `app/test/wave_q_uncertainty_ui_test.dart`

العدد: 32 ملفًا، جميعها داخل app/lib وapp/test وapp/docs. ملف التوثيق
النهائي وتحديثا الحالة والتسليم ضمن القائمة؛ لا تغييرات خارج النطاق.
