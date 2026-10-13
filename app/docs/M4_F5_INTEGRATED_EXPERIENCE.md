# M4-F5 — integrated patient routine experience

Source HEAD before phase: e9f05f4cd65ec122c183b602584e12bd9e395330.
Verdict: supported client navigation/readback integration implemented. Backend
limitations from F1/F2/F4 remain PARTIAL and are not concealed by UI polish.

Product details link to real RoutineEntry.product_id steps. Routine steps load
the owned associated product or an explicit unavailable state; they open the same
experiment view filtered by actual routine_entry_id, not a duplicate dashboard.
No matching experiment means no relationship in loaded records, with older-page
loading available. Morning/Evening show actual configured daily steps. Product
markers still do not create associations or infer use/clinical safety.

Routine → confirmed report → paginated history → related experiment → saved
evidence → existing Personal Skin Model → existing contextual assistance works
through real shared screens. Back retains route meaning and GET-refreshes routine
and PSM when returning. Home gets one small routine entry after existing Safety/
next-action sections. Its completion, baseline and observation semantics remain
server-derived. Reports now links to existing PSM and Experiment tab instead of
rendering another full experiment editor. Bottom navigation labels unchanged.

Confirmed product/experiment writes dispatch affected product/experiment/Home/
clinical GETs in the same session. Routine writes refresh owned routine/readback
then those GET projections. PSM opens/returns with its own authoritative GET;
no client-generated facts are injected and no routine/product/experiment records
are automatically sent to assistance. Failed related GETs use existing honest
error states rather than undoing confirmed persistence or claiming clinical success.

Safety/clinician panels precede feature actions in routine, experiments, product
library/details and Reports. Existing urgent guidance and clinical precedence are
retained. A negative `/users/me` consent read now notifies existing listeners
immediately; revoked consent clears open features, not only future API requests.
Related experiment/product search/detail/intelligence views bind their original session, clear private
search and stop on invalidation. Intelligence no longer starts a replacement
request for a different account from an old panel. Stale dialog actions cannot
save using a new account. No sensitive request payload is logged.

Light/Dark semantic surfaces and English UI preserved. Narrow dropdowns expand
within available width; routine/experiment routes use reduced-motion-aware shared
entry transitions. Existing native button/input semantics retained. 15 integrated
regressions include four theme/320px/200%/reduced-motion journeys, GET refresh,
full Back navigation, unavailable relationships, uncertain report, consent
revocation, reused-token account switch and delayed401/403/404/503. No automated
agent/comparison request or automatic assistance POST occurs. Tests use synthetic
wire contracts and explicitly deny any host other than flutter-tests.invalid.
Every new M4 wire fixture now explicitly denies production hosts. Existing tests are retained; two now scroll to actual offscreen targets after
Safety panels were promoted. The baseline-only widget fixture now explicitly
injects its experiment repository instead of exposing an unauthenticated live view. Full analyzer/suite results are in final report.

Preserved: guided camera, private images, comparison-ready boundaries, M3 PSM,
assistance, future Agent consent model. No new notifications, background planner,
comparison dates, AI intervention, prescriptions, backend/Azure/DB/provider/Tester
change, real OAuth call, live production integration test or deployment.

External QA: actual Android/iOS navigation/keyboard/VoiceOver/TalkBack, device
clock boundary behavior, draft disposal under OS lifecycle and integration against
Hussam-approved isolated contracts. Mock success is not production proof. Next
steps should resolve consolidated contract gaps before planning M5.
