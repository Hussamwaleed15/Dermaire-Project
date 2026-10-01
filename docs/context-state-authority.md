# Daily context authority

Chosen domain: daily context. The former Flutter screen simulated temperature and humidity,
seeded cycle day 12, and returned "Context saved" without writing anything. Home claimed
normal weather and the report claimed three weather exclusions. There was no backend
context model, endpoint, or measurement consumer. This was the highest-impact remaining
false context input for the Personal Skin Model. Rewards and measurement projections
remain separate future milestones.

## Paths and ownership

- Flutter ContextScreen -> ContextController -> ContextRepository -> ApiService ->
  authenticated GET/PUT /api/v1/context/{UTC date} -> DailyContext table.
- Home opens the same editor; post-check-in AnalysisScreen opens the same editor.
- Startup and authenticated entry refresh ContextController; account/session clear
  invalidates its snapshot and in-flight responses. Each editor opening reads the server.
- One row per owner/date; PUT replaces both optional values and supports clearing them.
  Reads for another day or owner return an explicit unrecorded snapshot.
- Account deletion deletes context rows before the user, including under enforced FKs.
- Existing startup create_all creates the new table without changing existing tables.

## Truth and limitations

Only user-reported unusual conditions and optional cycle day are persisted. Empty fields
are unknown, never inferred. No weather provider, weather exclusions, or automatic skin
score adjustment exists. Home, editor and report now state that limitation. No old demo
context is migrated because none was persisted.

Flutter has an in-memory server snapshot and an editor draft. Failed/ongoing reads hide
the snapshot as current truth; failed writes retain the draft and never announce success.
Refresh reads server values separately from the retained draft. A write timeout can mean
the server committed: refresh before retrying. PUT is idempotent for the same owner/date
and values. UTC dates keep grouping aligned with baseline. Context is daily and may be
edited separately from a check-in; it is not yet used as a model feature.

## Verification

Backend tests cover unknown values, owner isolation, validation, replacement, refresh,
commit failure, and account deletion. Flutter controller tests cover restart, stale reads,
offline writes, malformed/fake confirmation, and session clearing during a read.
