# DERMAIRE — مركز حالة المشروع

هذا الفهرس هو نقطة البداية الرسمية لمعرفة: **بنعمل إيه، عملنا إيه، وهنعمل إيه** في كل Track. التقارير القديمة داخل `docs/` تظل أدلة أو مراجع تاريخية، لكنها لا تُعتبر حالة حالية إلا إذا ربط بها ملف `STATUS.md` مع تاريخ وSHA واضحين.

## تقارير التراكات

| Track | التقرير | المسؤول | حالة التوثيق / التحقق | حالة التنفيذ |
|---|---|---|---|---|
| Backend | [backend/STATUS.md](backend/STATUS.md) | حسام وليد | Partially verified حالياً؛ source/CI verified عند PR #4، runtime غير متحقق | In progress — API واختبارات واسعة مع gaps تكامل وتشغيل |
| Azure / Infrastructure / Database | [azure-database/STATUS.md](azure-database/STATUS.md) | حسام وليد | Partially verified من الملفات والتاريخ؛ live state غير مفحوص | In progress تاريخياً؛ current live state Unknown |
| AI / ML | [ai/STATUS.md](ai/STATUS.md) | حسام وليد | Partially verified من المصدر؛ providers/clinical validation غير متحققين حياً | In progress — contracts/services موجودة، genuine model gates مفتوحة |
| Flutter | [flutter/STATUS.md](flutter/STATUS.md) | TBD | Unknown — يحتاج مالكاً وتحديثاً موثقاً | Unknown — غير متحققة، ولا تعني عدم وجود عمل |
| Testing / QA | [testing/STATUS.md](testing/STATUS.md) | TBD | Unknown — يحتاج مالكاً وتحديثاً موثقاً | Unknown — غير متحققة، ولا تعني عدم وجود عمل |

## معنى الحالتين

- **حالة التوثيق / التحقق** تصف جودة وحداثة الأدلة الموجودة في التقرير، لا حالة تنفيذ المنتج.
- **حالة التنفيذ** تصف التقدم الفعلي فقط عندما يدعمه دليل واضح.
- `Unknown` في أي عمود يعني **غير متحقق من الأدلة المتاحة**؛ لا يعني أن العمل غير موجود أو لم يبدأ.
- الاعتمادات بين التراكات تُلخص في كل `STATUS.md`، وتُنقل تفاصيلها إلى تقرير واحد داخل [`shared/`](shared/README.md) عند بدء التنسيق الفعلي.

## التقارير المشتركة

- استخدم [shared/REPORT_TEMPLATE.md](shared/REPORT_TEMPLATE.md) لأي عمل يشترك فيه شخصان أو أكثر، أو Trackان أو أكثر.
- الجرد الحالي أثبت اعتماداً فعلياً بين التراكات؛ سجلّه الموحد هو [AI ↔ Backend ↔ Azure/DB ↔ Flutter](shared/AI_BACKEND_AZURE_FLUTTER_HANDOFF.md).
- احتفظ بكل تقرير مشترك كسجل مستقل داخل `docs/shared/`، ولا تضع تفاصيله كاملة في أكثر من `STATUS.md`؛ أضف رابطاً إليه فقط لمنع التضارب.
- قواعد التسمية والتحديث موجودة في [shared/README.md](shared/README.md).

## قاعدة التحديث

1. لا تُسجل مهمة كـ **Completed / Verified** من غير رابط PR أو commit أو test evidence.
2. استخدم `Unknown` أو `TBD` عندما لا يوجد دليل؛ لا تعتمد على الذاكرة أو تقرير قديم.
3. حدّث تاريخ التقرير و`Last verified SHA` في نفس PR الذي يغيّر الحالة.
4. لا تستخدم حالة واحدة للتوثيق والتنفيذ معاً. لكل بند، سجل **Documentation / Verification status** و**Implementation status** كلما كان الفصل بينهما مطلوباً.
5. حالات التنفيذ المسموح بها: `Unknown`, `Planned`, `In progress`, `Blocked`, أو `Completed`. وحالات التوثيق/التحقق: `Unknown`, `Needs re-verification`, `Partially verified`, أو `Verified`.
6. راجع ملفات الحالة عند كل PR مؤثر، وعلى الأقل مرة أسبوعياً أثناء العمل النشط. إذا مر أكثر من 7 أيام، اعتبر حالة التوثيق بحاجة لإعادة تحقق، من دون تغيير حالة التنفيذ تلقائياً.
7. لا يحتوي التوثيق على أسرار أو connection strings أو بيانات مرضى أو لقطات تكشف إعدادات حساسة.

## لقطة تحقق 2026-11-19

- Baseline: [`62893d13dd1558d1c689297f8e23ced8e24fbdc4`](https://github.com/Hussamwaleed15/Dermaire-Project/commit/62893d13dd1558d1c689297f8e23ced8e24fbdc4)، وهو merge commit لـ[PR #20](https://github.com/Hussamwaleed15/Dermaire-Project/pull/20).
- نطاق الجرد: source tree، docs، git history، وpublic GitHub PR/check metadata. لم يشمل Azure/DB/provider runtime أو secrets أو patient data.
- لم تتغير تقارير Flutter أو Testing؛ استُخدمت ملفات Flutter handoff كأدلة read-only فقط.
