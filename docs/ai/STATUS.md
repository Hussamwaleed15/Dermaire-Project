# AI / ML — تقرير الحالة الرسمي

| الحقل | القيمة |
|---|---|
| Shared between people | حسام وليد؛ تسليمات Flutter الموثقة من عمرو؛ المراجع السريري/الأمني المستقل `TBD` |
| Tracks / Departments | AI / ML؛ Backend؛ Flutter؛ Azure / Infrastructure |
| Owner | حسام وليد |
| Documentation / Verification status | Partially verified — جرد مصدر ووثائق وCI عند SHA أدناه؛ لا يوجد تحقق حي من providers أو clinical validation |
| Implementation status | In progress — عقود وخدمات ومسارات واختبارات منفذة، مع مزودات حقيقية غير مكتملة أو غير متحققة سريرياً |
| Last updated | 2026-11-19 (Africa/Cairo) |
| Last verified SHA | [`62893d13dd1558d1c689297f8e23ced8e24fbdc4`](https://github.com/Hussamwaleed15/Dermaire-Project/commit/62893d13dd1558d1c689297f8e23ced8e24fbdc4) |

## بنعمل إيه الآن

نحوّل قدرات AI الموجودة إلى inventory قابل للتدقيق: ما هو deterministic، وما يستدعي provider خارجياً، وما هو مجرد contract، ثم نغلق فجوات البيانات والتحقق.

## عملنا إيه — Verified

- توجد عقود inference fail-closed تمنع تحويل unavailable إلى نتيجة مريض، وتطلب provenance للنتيجة المولدة: [`backend/app/services/model_providers.py`](../../backend/app/services/model_providers.py).
- توجد خدمات Azure Vision/OpenAI/Content Safety مع flags وtimeouts وفشل degraded/fallback؛ وجود الكود أو الإعداد لا يثبت reachability أو clinical validity: [`azure_vision.py`](../../backend/app/services/azure_vision.py)، [`azure_openai.py`](../../backend/app/services/azure_openai.py)، [`azure_safety.py`](../../backend/app/services/azure_safety.py).
- تحليل الصور المحلي الحالي proxy قائم على خصائص الصورة، موسوم non-diagnostic، وليس نموذجاً جلدياً مدرباً أو Azure clinical analysis.
- توجد routes/services واختبارات provider/safety/contextual/personal-skin-model داخل `backend/`. نجاح CI على [PR #4](https://github.com/Hussamwaleed15/Dermaire-Project/pull/4) يثبت سلوك المصدر المختبر، لا دقة سريرية ولا provider حي.
- Flutter يستهلك حالات unavailable/contracts ولا يجوز له اختراع نتيجة أو clearance؛ التسليم موثق في [`app/docs/M3_F4_HUSSAM_HANDOFF.md`](../../app/docs/M3_F4_HUSSAM_HANDOFF.md) و[`app/docs/FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md`](../../app/docs/FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md).

## حالة التنفيذ بالتفصيل

| المجال | Implementation status | Documentation / verification status | الدليل / الحد |
|---|---|---|---|
| Contextual assistant + safety fallback | In progress | Partially verified | routes/services/tests موجودة؛ provider reachability والحكم السريري غير متحققين |
| Image proxy measurements | Completed كتنفيذ proxy فقط | Verified من المصدر، unverified سريرياً | خوارزمية محلية versioned؛ ليست تشخيصاً ولا model artifact |
| Comparison / Agent model boundary | Planned / Blocked خارجياً | Verified كـfail-closed | provider الفعلي disabled/unavailable؛ لا artifact validated أو private-image transport مثبت |
| Personal skin model/history contracts | In progress | Partially verified | API/services/tests موجودة؛ لا دليل dataset/training أو outcome validation |
| Dataset, consent, licensing | Unknown | Unknown | لا dataset manifest/datasheet، license ledger، consent provenance أو DUA مؤكدة في الشجرة |
| Training/reproducibility | Unknown | Unknown | لم يُعثر على training pipeline/notebooks أو split manifest أو checkpoint/weights/model card |
| Metrics/validation | Unknown | Unknown | لا sensitivity/specificity/calibration/subgroup metrics أو independent clinical validation مرتبطة بartifact |

## هنعمل إيه — أولويات حسام القابلة للقياس

1. **AI inventory gate:** manifest لكل capability يربط use case بـendpoint/provider/flag/data class/owner وحالة `deterministic|external|disabled`؛ القبول: تغطية 100% لمسارات AI وعدم وجود capability بلا owner أو safety boundary.
2. **Data/model evidence gate:** قبل تدريب أو تفعيل model، إضافة datasheet + license/consent provenance + immutable split manifest + model card/artifact hash؛ القبول: لا تداخل patient بين splits، reproducible run واحد، ومقاييس uncertainty/subgroups معلنة.
3. **Integration/clinical gate:** contract tests من Flutter→Backend→provider adapter لحالات success/timeout/degraded/withdrawn consent، ثم مراجعة سريرية وأمن/خصوصية مستقلة؛ القبول: fail-closed بلا synthetic diagnosis، artifact/version ظاهر، وعدم إرسال بيانات قبل consent وسياسة retention معتمدة.

## Blockers / Unknowns

- datasets ومصدرها وتراخيصها/الموافقات، preprocessing، splits، training runs، weights/checkpoints، model registry، metrics والـclinical validator: `Unknown`.
- حالة Azure AI endpoints الحية، quotas، region، cost وprivate networking: `Unknown`؛ لم يتم فحصها.

## Dependencies / Cross-track handoffs

- [تقرير التكامل المشترك](../shared/AI_BACKEND_AZURE_FLUTTER_HANDOFF.md).
- حسام يملك AI/Backend/Azure/API contracts؛ عمرو يملك Flutter consumer. المراجع المستقل للclinical/privacy/security ما زال `TBD`.

## يحتاج مراجعة مستقلة

- Clinical safety/claims، dataset consent/licensing، privacy/retention، threat model للصور/prompts، والتحقق الإحصائي/التحيز.

## Evidence

- [PR #4](https://github.com/Hussamwaleed15/Dermaire-Project/pull/4) و[merge commit](https://github.com/Hussamwaleed15/Dermaire-Project/commit/bf979ef99581b71314859ea3fb482c1fe79fe6fa).
- [`docs/real-ai-vision-production.md`](../real-ai-vision-production.md) مرجع تاريخي؛ لا يثبت الحالة الحية الحالية.
