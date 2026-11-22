# Testing / QA — تقرير الحالة الرسمي

| الحقل | القيمة |
|---|---|
| Shared between people | TBD |
| Tracks / Departments | Testing / QA؛ كل التراكات حسب نطاق الاختبار |
| Owner | TBD — لا يوجد اسم مؤكد |
| Documentation / Verification status | Unknown — لم يتم التحقق من الأدلة الشاملة الحالية |
| Implementation status | Unknown — غير متحققة من الأدلة المتاحة، ولا تعني عدم وجود عمل |
| Last updated | 2026-11-19 (Africa/Cairo) |
| Last verified SHA | TBD |

## بنعمل إيه الآن

TBD بعد تحديد Owner وخطة الاختبار الشاملة. نتائج اختبار PR منفرد تُسجل في تقرير الـTrack المعني ولا تعني تلقائياً اعتماد المشروع كله.

## عملنا إيه — Verified

- لا توجد حالة QA شاملة مؤكدة في هذا التقرير حتى الآن.

## In progress

- Unknown.

## هنعمل إيه

- تحديد test matrix لكل Track والبيئات والمسؤول عن التوقيع.
- ربط النتائج بالـcommit SHA والـworkflow/run أو تقرير يدوي موثق.
- فصل unit/integration/UI/security/performance/UAT وعدم جمعها تحت كلمة “tested” فقط.

## Blockers / Unknowns

- Owner، coverage المقبولة، البيئات، والأجزاء التي لم تُختبر: `TBD`.

## Dependencies / Cross-track handoffs

| الاعتماد / التسليم | المسؤول / Track التابع | الحالة | المطلوب لتأكيد الاعتماد | التقرير المشترك |
|---|---|---|---|---|
| معايير القبول وأدلة الاختبار لكل Track | Testing / QA + الـTrack المعني؛ الملاك `TBD` | Potential / planned requirement — غير مثبت كتنفيذ شامل | test matrix، البيئة، SHA، نتائج قابلة للتتبع، وتأكيد مسؤول التوقيع | TBD — يُنشأ من [القالب](../shared/REPORT_TEMPLATE.md) عند بدء التنسيق الفعلي |

## Decisions

- لا تتحول المهمة إلى `Verified` بسبب نجاح اختبار محلي غير مربوط بـSHA ودليل.

## Evidence

- TBD.
