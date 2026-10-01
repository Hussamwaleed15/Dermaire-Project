# Products: backend state authority

## Why this domain first

Products had a complete authenticated backend CRUD API but production Flutter
only persisted edits in SharedPreferences. Empty server lists and failures fell
back to legacy local data or four seeded products. The model expected camelCase
while the API emitted snake_case, so real responses could fail to decode.
These gaps affect every product action and are isolated from other domains.

## Read and write paths

Before: ProductsFeatureTab / editor / detail -> ProductsController ->
RemoteProductRepository -> GET /products. Nonempty responses were copied into
LocalProductRepository (`dermaire_products_v2`); all edits used saveProducts,
writing only that local list. LocalProductRepository seeded missing storage.
An obsolete ProductsTab / AddProductScreen / InteractionScreen used a second
DermaireState.products list and static catalog, details and fake rewards.

After sign-in the onboarding entry point starts a fresh products load.
After: the same feature screens -> ProductsController -> RemoteProductRepository
-> ApiService -> authenticated GET/POST/PATCH/DELETE /api/v1/products ->
user-scoped SQLAlchemy Product rows. POST and PATCH responses supply the
confirmed IDs, fields and timestamps. A successful empty GET clears the list.
Explicit API mapping covers ingredients, routine/experiment flags, dates and
other snake_case fields. Date and tag schema gaps are filled without migrations.
The obsolete screens, second list, seeded repository and local reward increment
on product creation are removed. MemoryProductRepository is injection-only test
support with an empty default, never selected by the production constructor.

## Offline, failures and session boundaries

The controller retains the last confirmed list in memory during a session.
Failed refreshes show a stale-data warning and retry control while keeping that
list readable. Failed writes do not change the confirmed list or show success;
an online refresh is required before retry, including when a server may have
committed a write whose response was lost. No automatic offline queue is added.
Draft forms remain available for manual retry. The server remains authoritative
for duplicate names, ownership and experiment deletion/archive protections.
The UI never claims it ended an experiment as a side effect of deletion.

The existing memory-only auth policy is preserved: restart requires sign-in and
fresh backend reads. No product health data is newly persisted. Session init,
logout, expiry, 401 and deletion still clear legacy SharedPreferences data.
Controller generations prevent late reads/writes from restoring cleared data.
Refresh and mutation are serialized. Cache reads do not manufacture products.

## Scope and verification

Focused API tests cover CRUD persistence, fields/dates/tags, rejected changes,
empty lists, ownership and experiment protections. Flutter tests cover server
responses/IDs, controller recreation and refresh, empty-list invalidation,
server failure/stale cache, no fake success and logout during an outstanding read.
Existing session/account-deletion suites remain required regression checks.
Baseline, experiment workflow, reports, home metrics and reward balance remain
separate milestones; their existing static content is not a product catalog.
