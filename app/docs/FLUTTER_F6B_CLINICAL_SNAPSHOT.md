# F6b — Server-owned combined clinical read

2026-10-18. Verified actual patient and doctor clinical_snapshot routes/DTOs/service,
final current-auth/original-grant gates, Home projection and current PSM2 contract.

Patient Home (and Reports) and authorized doctor Patient detail link to a real
combined snapshot screen. GET /clinical-snapshot returns patient schema1; doctor
GET /clinical-snapshot/patients/id returns schema2 with actual reader and original
VIEW grant. Flutter validates exact role/owner/patient/grant, PostgreSQL repeatable-
read marker, database-only atomic scope, external-not-atomic boundary, false replay/
clearance flags and identical canonical Safety/clock across Safety/review/Home/PSM.
JSON key order alone cannot manufacture a source mismatch.

Doctor connection is checked before and after the bundle; account/cover/background
or a replacement original grant clears displayed content and rejects late results.
The route is GET-only in the guarded Flutter transport. Permission/500/503 or a
malformed/contradictory bundle yields unavailable. Flutter never assembles
independent requests and claims transaction consistency; existing separate screens
remain separately timestamped reads. This optional actual bundle does not silently
replace all working independent controllers or claim continuous freshness.

Home validation is shared with the existing HomeController without changing its
legacy contract. Snapshot-day structured observation completion uses actual UTC
observation_status, independent of confirmed measurement and baseline. Report-only
records create no invented scores. Current-day completion requires actual matching
evidence; future recorded evidence is rejected. UI says snapshot UTC day, not a
continuously current Today label after time passes. Deterministic PSM evidence and
patient-visible vs doctor-authorized review remain distinct; no old public decision
is promoted when the current decision is private. One transaction is not medical
clearance or an atomic claim about image bytes, external providers or later writes.

Source review caught one final lint in the previous invitation grant recheck;
fixed here with no change to its authority behavior. Native/backend/Tester/provider
systems remain untouched, and no PostgreSQL/production call was made by Flutter.

Focused31 tests: report-only versus measurement, role/schema/owner/grant, shared
clock and Safety disagreement, scope/atomicity/clearance/future/completion/PSM
malformation, one bundle without aggregation, actual selected doctor readback,
401/403/404/500/503, late hide/logout/account switch/old401, replacement grant during
reply, GET-only transport and320px/200% light/dark rendering. All mock transports
reject real hosts. No actual device runtime or deployed PG availability claimed.
