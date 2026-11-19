# Azure / Infrastructure / Database — تقرير الحالة الرسمي

| الحقل | القيمة |
|---|---|
| Shared between people | حسام وليد؛ باقي المشاركين `TBD` |
| Tracks / Departments | Azure / Infrastructure / Database؛ الاعتمادات المشتركة `TBD` |
| Owner | حسام وليد |
| Documentation / Verification status | Unknown — لم يتم إجراء تحقق حي ضمن هذا التقرير |
| Implementation status | Unknown — غير متحققة من الأدلة المتاحة، ولا تعني عدم وجود عمل |
| Last updated | 2026-11-19 (Africa/Cairo) |
| Last verified SHA | TBD |

## بنعمل إيه الآن

الحفاظ على سجل دقيق يفصل بين تصميم البنية، الحالة المرصودة، وأي تغيير فعلي في Azure أو Database.

## عملنا إيه — Verified

- لا توجد تغييرات Azure أو Database منفذة أو متحققة كجزء من إنشاء هذا التقرير.

## In progress

- Unknown.

## هنعمل إيه

- توثيق inventory غير حساس، البيئات، الملكية، وخطة التحقق لكل بيئة.
- ربط أي migration أو deployment أو restore rehearsal بموافقة ونطاق ودليل منفصل.
- تسجيل التكلفة والمخاطر وخطة rollback قبل أي تغيير مؤثر.

## Blockers / Unknowns

- الحالة الحية لـAzure resources، deployments، database revision، backups، وmonitoring: `TBD / غير متحققة هنا`.
- أسماء المشاركين وأصحاب الموافقة: `TBD`.

## Dependencies / Cross-track handoffs

| الاعتماد / التسليم | المسؤول / Track التابع | الحالة | المطلوب لتأكيد الاعتماد | التقرير المشترك |
|---|---|---|---|---|
| AI ↔ Azure resource and security requirements | AI + Azure / Infrastructure؛ الملاك التفصيليون `TBD` | Potential / planned requirement — غير مثبت كتنفيذ | متطلبات موارد وأمان غير حساسة، حدود البيانات، الملكية، التكلفة، الموافقات، ودليل PR/قرار | TBD — يُنشأ من [القالب](../shared/REPORT_TEMPLATE.md) عند بدء التنسيق الفعلي |

## Decisions

- التقارير التاريخية ليست إثباتاً تلقائياً للحالة الحالية.
- لا تُدرج أسرار أو connection strings أو بيانات مرضى في GitHub.
- أي تغيير حي أو ذو تكلفة يحتاج مسار موافقة مستقل؛ هذا الملف لا يمنح تلك الموافقة.

## Evidence

- TBD. عند التحديث، استخدم روابط PR/commit وأدلة منزوعة الأسرار فقط.
