# Personal Skin Model v1

Authenticated `GET /api/v1/personal-skin-model` is an owner-only, deterministic
read-time projection. No new canonical state, migration, LLM or external calls.
Typed contract: `app/schemas/personal_skin_model.py`; version `psm-v1.0`.
Errors remain HTTP failures, never empty success or seeded fallback.

## Inputs and exclusions

Profile v2 contributes only explicitly disclosed `primary_goals` as orientation,
not trajectory evidence. Availability means a profile envelope exists. Sensitive
attributes, cycle day, legacy profile defaults, free text and photos are excluded
from derivation/output. No undisclosed attributes are inferred.

Baseline uses the existing frozen first five distinct UTC unlinked confirmed
measurement days. History uses confirmed manual measurements or image-property
proxies, and validated v1 reports with server timestamp/user-report provenance.
Unconfirmed legacy, simulated, future and local-only records cannot supply evidence.
Earliest timestamp then ID per UTC day prevents duplicate-day inflation.

Daily context uses explicitly true/false unusual conditions, joined by owner and
server check-in UTC date. Unknown is not false. Context is mutable; its ID and
update timestamp identify the current record, not an immutable historical snapshot.
Products supply current owner inventory IDs/statuses/provenance only. Inventory
is not verified exposure or proof of product effects. Routine is excluded: product
membership and self-reported adherence do not establish authoritative usage events.

## Rules

Measurements require five valid baseline days from one source, then at least three
later distinct days from that same source within 14 elapsed days. Use latest five
eligible recent days. Compare mean with this user's baseline, never population
averages. Threshold is max(10 score points, twice within-user baseline standard
deviation). Change requires magnitude >= threshold plus >= two-thirds recent
values on the mean-change side of the reference. Large inconsistent differences
remain unknown; differences below threshold are stable within the tracking threshold.
Manual and proxy sources never mix. Higher/lower scores do not diagnose disease or
automatically imply health improvement. Proxies are not clinical measurements.

Reports require six distinct days in 28 elapsed days, including latest three within
14 days. Compare symptom-presence counts in first three versus latest three:
absolute difference >=2 produces a limited frequency finding. Unlisted symptoms
mean not reported, not confirmed absence. Symptoms have no severity scale.
Unanimous latest three overall-change reports produce a limited self-reported
better/same/worse finding. Discordant reports yield no overall conclusion.
Channels remain separate, preserving potentially conflicting evidence.

Associations require >=3 paired report days per explicitly true/false unusual
conditions group, all within 14 days. Worse-report rate gap >=two-thirds yields a
limited association with explicit noncausal wording. No product effects, cycle
analysis or causal adjustment. Unsupported associations remain absent with an
explicit unmet-evidence requirement.

## Strength and freshness

Strength measures tracking evidence support, not medical certainty/probability:
`none` without trajectory findings, `limited` for report/context findings,
`moderate` for eligible same-source measurement comparisons. Overall strength is
the strongest trajectory finding; each finding preserves its own strength. No high
confidence or percentage certainty. Thresholds are conservative engineering rules,
not clinically validated. Provenance lists source, ID, fields, timestamp and kind;
each finding includes its rule and numeric comparison where applicable.

Recency uses latest confirmed skin evidence: missing, fresh (<=14 UTC calendar
days) or stale (>14). Stale data yields no current findings. Comparison windows use
elapsed UTC time. Profile/inventory/context alone never refresh skin evidence.
Sufficiency exposes distinct-day counts, excluded rows, baseline readiness, age,
latest timestamp and unmet requirements. One supported channel can coexist with
insufficiency in another.

States: `no_data`, `insufficient_data`, `no_meaningful_change`, `meaningful_change`,
`stale`. No meaningful change is valid; it is not proof of medical health.

## Examples

- Products and goals without observations: no_data, strength none.
- Eight same-day reports: insufficient_data, one confirmed day.
- Five manual baseline days at 50, three later days at 50: stable, threshold 10,
  no_meaningful_change; continue tracking.
- Same baseline and three later days at 70: higher tracking scores, moderate
  evidence, meaningful_change; no diagnostic or product-effect claim.
- Three worse reports with unusual conditions versus three same without:
  limited association, explicitly not causation.
- Last skin evidence 15 days ago: stale, current trajectory unknown.

## Integration and scope

Flutter remains unchanged: existing ReportsTab includes demo report flows;
replacing that UI would expand this milestone. The API is ready for a future
server-driven UI with loading/insufficient/failure states. No seeded fallback.
Existing auth/session/account deletion, doctor, profile, baseline, history, context
and product routes are preserved. Derived views persist nothing and need no extra
deletion hook. No production deployment or production mutation in this milestone.

## Milestone verification

Final full backend suite: **156 passed**, including **25 Personal Skin Model cases**.
Existing auth/session, account deletion, profile, baseline, history, context,
products and doctor regressions passed. Sixteen existing Starlette 422 deprecation
warnings remain. `git diff --check` passed. Flutter unchanged, so Flutter tests and
analysis were not required. Tests used isolated SQLite fixtures; no production
accounts/data/secrets were changed.
