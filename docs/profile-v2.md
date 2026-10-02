# Profile v2

The existing users row is authoritative: GET /api/v1/users/me and PATCH /api/v1/users/skin-profile. Registration inputs are unchanged. No Personal Skin Model, recommendation or inference is implemented.

Age is an optional age band, rather than DOB, to avoid collecting a precise birth date. It is user-maintained and does not auto-age. Sex, age, care status and menstrual context support explicit prefer_not_to_say; null means undisclosed/removed. Hormonal disclosure distinguishes disclosed, none_reported and prefer_not_to_say. Hormonal details require disclosed status; opting out clears details. Cycle applicability is never inferred from sex; every user can choose not_applicable or opt out.

profile_context stores age_band, sex, sensitivities_allergies, dermatologist_care, medications_treatments, primary_goals, hormonal_disclosure, hormonal_context and menstrual_context. Existing skin_type, skin_concerns and selected_goal remain readable. Arbitrary historical concerns/goals are preserved, not backfilled into disclosed answers. Historical default concerns/goals have uncertain provenance; future modeling must obtain confirmation before treating legacy values as disclosures. New accounts have no assumed concern or goal.

PATCH: omitted root or nested fields are preserved; explicit null clears a field; profile_context:null clears all context; arrays replace rather than append. Empty lists mean no entries, not confirmed absence of allergies/treatments. skin_concerns:null clears to [] for legacy readers. Unknown fields are rejected. Sensitive values are never copied to update audit logs. Data resides on users and is removed through existing real account deletion. No local persistent canonical profile is introduced; UI edits are drafts and server responses confirm writes.

Intended future uses (not implemented): age/sex physiological context; skin type baseline characteristics; concerns and goals outcome selection; sensitivities tolerated-product context; care and treatments interpretation of interventions; explicitly disclosed hormonal/cycle context temporal interpretation. Answers must not be used to infer undisclosed attributes. Free-text lists accept user-described allergies/treatments/goals without inferring diagnoses or prescribing anything.

## Manual migration: review and apply externally BEFORE deploying backend

No Alembic exists; create_all does not alter existing tables. Production PostgreSQL statements are idempotent and preserve historical data:

```sql
BEGIN;
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_context JSON NULL;
ALTER TABLE users ALTER COLUMN selected_goal DROP NOT NULL;
ALTER TABLE users ALTER COLUMN selected_goal DROP DEFAULT;
ALTER TABLE users ALTER COLUMN skin_concerns DROP DEFAULT;
COMMIT;
```

Do not run against production as part of this milestone. Existing local SQLite databases also need `ALTER TABLE users ADD COLUMN profile_context JSON;` once (check PRAGMA table_info first); recreate disposable development databases if selected_goal has a legacy NOT NULL constraint. Fresh test/development schemas need no migration.

Flutter provides three optional progressive sections, retry on failed load/save, explicit clear choices, and skip preserving saved values. Settings allow subsequent correction/removal. A failed save never advances. No new animations were added.
