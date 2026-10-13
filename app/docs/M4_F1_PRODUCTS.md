# M4-F1 — personal products

Verdict: supported personal-product scope implemented; verified catalog,
atomic edit protection and recoverable idempotent creation are unsupported.
Starting source: a2ff1466b7307be2850d6669f9d624cd62dd271b. Inspected the three
October architecture/agent/roadmap audits and current product API/schema/models.

The actual contract is owned `/products` CRUD, not a verified public catalog.
List has category/status/marker filters but no pagination. Detail includes
user_id, enums, lists, timestamps, cosmetic notes and optional image URL.
`in_routine`/`in_experiment` are markers, not relationships or evidence of use.
RoutineEntry.product_id is the real routine association. No clinical safety
is inferred from inventory, ingredient text or category illustration.

Remote DTOs fail closed on unknown enums, required fields, timestamps and owners.
Creates and minimal PATCHes require matching by-ID GET readback. PATCH checks
the last server updated_at before sending, but cannot atomically lock races.
Delete requires GET404 after DELETE204; failed readback keeps the record.
Pending writes reject duplicate taps. Uncertain create disables further creates
in that controller/session even after refresh; there is no blind POST retry.
GET failures retain confirmed records with explicit stale warning. 401 clears
the session; old responses, disposed controllers and old editors cannot commit.
Editor drafts clear on session change; profile concerns are not silently copied.
Inactive/archived-only libraries remain reachable. Charcoal surfaces use tokens.

Changes: product model, repository, controller, products UI, narrow authenticated
patientResource transport, actual-wire fixtures and m4_products_test.
Shared transport formatting/brace lint cleanup has no intended behavior change.

Verification: full Flutter analyzer and suite gate; 18 new contract/lifecycle
regressions plus existing product widget/search/theme tests. Production HTTP is
denied by global test configuration. All data synthetic; no OAuth/live service,
production build/deploy or device QA. Exact full count in the final report.
Backend, tester and inherited SwiftPM files untouched.
