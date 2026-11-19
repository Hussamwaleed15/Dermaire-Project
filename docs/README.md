# DERMAIRE — مركز حالة المشروع

هذا الفهرس هو نقطة البداية الرسمية لمعرفة: **بنعمل إيه، عملنا إيه، وهنعمل إيه** في كل Track. التقارير القديمة داخل `docs/` تظل أدلة أو مراجع تاريخية، لكنها لا تُعتبر حالة حالية إلا إذا ربط بها ملف `STATUS.md` مع تاريخ وSHA واضحين.

## تقارير التراكات

| Track | التقرير | المسؤول | الحالة الحالية |
|---|---|---|---|
| Backend | [backend/STATUS.md](backend/STATUS.md) | حسام وليد | Verified جزئياً |
| Azure / Infrastructure / Database | [azure-database/STATUS.md](azure-database/STATUS.md) | حسام وليد | Unknown — يحتاج تحديثاً موثقاً |
| AI / ML | [ai/STATUS.md](ai/STATUS.md) | حسام وليد | Unknown — يحتاج تحديثاً موثقاً |
| Flutter | [flutter/STATUS.md](flutter/STATUS.md) | TBD | Unknown — يحتاج مالكاً وتحديثاً موثقاً |
| Testing / QA | [testing/STATUS.md](testing/STATUS.md) | TBD | Unknown — يحتاج مالكاً وتحديثاً موثقاً |

## التقارير المشتركة

- استخدم [shared/REPORT_TEMPLATE.md](shared/REPORT_TEMPLATE.md) لأي عمل يشترك فيه شخصان أو أكثر، أو Trackان أو أكثر.
- احتفظ بكل تقرير مشترك كسجل مستقل داخل `docs/shared/`، ولا تضع تفاصيله كاملة في أكثر من `STATUS.md`؛ أضف رابطاً إليه فقط لمنع التضارب.
- قواعد التسمية والتحديث موجودة في [shared/README.md](shared/README.md).

## قاعدة التحديث

1. لا تُسجل مهمة كـ **Completed / Verified** من غير رابط PR أو commit أو test evidence.
2. استخدم `Unknown` أو `TBD` عندما لا يوجد دليل؛ لا تعتمد على الذاكرة أو تقرير قديم.
3. حدّث تاريخ التقرير و`Last verified SHA` في نفس PR الذي يغيّر الحالة.
4. كل بند له حالة واحدة: `Unknown`, `Planned`, `In progress`, `Blocked`, `Completed`, أو `Verified`.
5. راجع ملفات الحالة عند كل PR مؤثر، وعلى الأقل مرة أسبوعياً أثناء العمل النشط. إذا مر أكثر من 7 أيام، اعتبر الحالة بحاجة لإعادة تحقق.
6. لا يحتوي التوثيق على أسرار أو connection strings أو بيانات مرضى أو لقطات تكشف إعدادات حساسة.
