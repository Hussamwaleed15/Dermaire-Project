DERMAIRE --- PROJECT MASTER PLAN & CROSS-ACCOUNT HANDOFF
Version: 1.0
Prepared: 12 November 2026 (Africa/Cairo)
Purpose: Canonical project-wide context document for transferring
Dermaire work to another ChatGPT account.
Repository: https://github.com/Hussamwaleed15/Dermaire-Project\
Branch: main
Verified repository HEAD at preparation:
b995873f2b76e0c37a08f23fbf40322174aba6fe (24 October 2026)
How to use this document: Read it as the project-wide source of
context and decision boundaries, not as proof that every planned
capability is implemented. It intentionally separates product vision,
approved decisions, current implementation evidence, blocked
dependencies, and open questions. Before changing code or making
current-status claims, inspect the live repository and its newest
documentation.

1. Executive Overview
Dermaire is a Longitudinal Personal Skin Health System. It is not
merely an AI skin scanner, a photo-analysis app, a skincare chatbot, a
product recommender, or a beauty application.

Its purpose is to help people observe their skin, understand changes,
manage interventions, track outcomes, compare evidence over time, learn
from their own history, and collaborate with clinicians through
consent-based access.

The product is designed around a continuous loop:

Observe → Understand → Change / Experiment → Track → Compare → Learn →
Adapt

Safety is above the entire loop. Safety guidance, uncertainty,
clinician instructions, consent, and privacy must take precedence over
engagement, routine completion, AI suggestions, visual effects, or
product goals.

Dermaire should support a broad range of skin diseases, symptoms, and
concerns from the beginning. It must not be architected as a product for
one disease only.

The scientific and product differentiator is the combination of: -
Longitudinal personal skin-health records. - Structured patient
observations. - Standardized image capture and evidence provenance. -
Personal context and potential confounding factors. - Routine and
intervention tracking. - N-of-1 / within-person experiment capabilities
where scientifically and clinically appropriate. - Honest comparison and
uncertainty. - Clinician collaboration and patient-controlled
permissions. - Constrained AI assistance that explains evidence without
replacing medical judgment.

The N-of-1 experiment engine is an important component of Dermaire, but
it is not the entirety of the product.
2. Problem Statement
Most consumer skin applications focus on isolated interactions: - Take a
selfie. - Receive a generic skin score or product recommendation. - Try
a product. - Return later without a reliable record of what changed or
why.

This creates several problems:
1. Fragmented history: Users cannot reliably reconstruct when a
   concern started, how it changed, and what they were using at the
   time.
2. Uncontrolled interventions: Several products or routine changes
   may happen together, making outcomes difficult to interpret.
3. Inconsistent observations: Different lighting, angle, distance,
   and image quality can make visual comparisons misleading.
4. Missing context: Skin changes can coincide with sleep, stress,
   hormones, weather, medication, diet, friction, and many other
   factors.
5. False certainty: A visual model or chatbot can overstate what a
   photograph or incomplete history proves.
6. Weak clinician handoff: Patients often cannot provide a
   structured, longitudinal account of symptoms, products,
   interventions, and outcomes.
7. Poor continuity: A single analysis rarely becomes a useful,
   persistent health journey.
Dermaire addresses the system-level problem: how to build a trustworthy
personal record and learning workflow around skin health, rather than
another isolated AI output.
3. Product Vision, Mission & Positioning
3.1 Vision
Make personal skin health more understandable over time by connecting
observations, context, interventions, outcomes, and professional
guidance in one coherent system.
3.2 Mission
Help users: - Notice and document meaningful skin changes. - Understand
what information is known, unknown, stale, or inferred. - Track routines
and interventions responsibly. - Compare only evidence that is genuinely
comparable. - Recognize when professional review is appropriate. - Share
an organized history with a clinician when they choose.
3.3 Positioning
Dermaire = Personal Skin Health System.

It is not: - A doctor replacement. - An autonomous diagnostic system. -
A beauty filter. - A product-selling funnel. - A generic conversational
chatbot. - A claim that every visible skin change can be measured
accurately from a phone camera.

The system supports care and informed tracking; it does not replace
medical professionals.
4. Core Product Model
4.1 The longitudinal loop
Observe
Collect structured observations, symptoms, changes, images where
appropriate, and user-reported context.
Understand
Connect current and historical evidence, show provenance and
uncertainty, surface clinician guidance, and explain what the available
information does and does not support.
Change / Experiment
Support tracking of routines, products, and interventions. Where
appropriate, use controlled within-person experiments without allowing
the app to autonomously prescribe or alter treatment.
Track
Record actual user-reported adherence and changes over time. Missing
records must remain unknown, not be converted into failure or
non-adherence.
Compare
Compare authorized, sufficiently comparable observations or plan-linked
image pairs. Do not invent a comparison score, fixed schedule, or
clinical meaning.
Learn
Show evidence-based patterns and limitations. Associations must not be
presented as causation.
Adapt
Help users decide what to document or discuss next. Clinical decisions
remain with the clinician and the user in the appropriate care context.
4.2 Safety layer
Safety is a system-wide authority layer: - Urgent safety guidance takes
priority over all ordinary UI. - Clinician-authored instructions and
review states remain visible. - Missing information never means
"safe". - Stale information cannot clear an urgent state. - AI must not
override deterministic safety logic or clinician authority. - The
product must clearly distinguish self-care information from medical
evaluation.
5. Users, Roles & Journeys
5.1 Patient
The patient owns their data and controls consent and sharing.

Main journey: 1. Register or sign in. 2. Complete required safety
acknowledgement and profile/onboarding steps. 3. Record a concern or
observation. 4. Capture or upload an image when appropriate and
consented. 5. View the authoritative status and history. 6. Add context
and track routine/intervention activity. 7. Review evidence and
comparisons when available. 8. Use the contextual assistant for
explanations and preparation. 9. Connect with a clinician when desired
or when review is indicated. 10. Revoke access or delete the account
through supported workflows.
5.2 Doctor / Clinician
Clinician access is separate from patient access and must be
deny-by-default.

Potential capabilities: - Authenticated clinician account. - Patient
connection through a real backend-issued mechanism. - Explicit patient
consent. - VIEW and EXPORT as separate permission scopes. - Patient
timeline and relevant history. - Clinician-authored notes and review
decisions. - Follow-up plans. - Secure patient-doctor messaging. -
Patient-visible instructions. - Controlled export/report workflow.

A stored role does not prove a professional license. The product must
not claim clinician verification unless the verification process
actually exists.
5.3 Project / Admin roles
Administrative access must be explicit and least-privileged. Admin
status must not be used as a shortcut around patient consent or clinical
access rules.
6. Skin Context & Evidence Model
The Personal Skin Health System must account for more than images and
products.

Relevant factors discussed for the product include: - Weather,
temperature, humidity, and UV exposure. - Menstrual and broader hormonal
changes. - Stress. - Sleep. - Medication. - Diet. - Smoking. - Sweat and
exercise. - Touching, picking, or squeezing. - Hair products. - Makeup,
cosmetics, and sunscreen. - Over-washing, scrubbing, and exfoliation. -
Routine adherence. - Unplanned products and interventions. - Friction
and other environmental exposures.

These are possible contextual variables, not proven causes. The product
must preserve the source and certainty of each factor.
6.1 Evidence provenance
Every relevant item should be distinguishable as: - patient_reported -
system_observed - deterministic_derived - clinician_authored -
ai_inferred

Where relevant, show: - Source. - Timestamp. - Unit. - Freshness /
age. - Confidence or quality limitations. - Whether the information is
missing, unknown, stale, partial, or unavailable.

Do not convert a missing field to a normal value. Do not treat a
self-reported factor as independently verified.
6.2 Contextual interpretation
A relationship between weather, hormones, sleep, stress, medication, or
product use and a skin change is not automatically causal.

The system may identify temporal associations or prompt the user to
record missing context. It must not claim to have statistically
neutralized confounders unless a validated analysis actually does so.
7. Scientific & Clinical Product Engines
7.1 Structured observation engine
Capture: - Concern / symptom. - Body or skin location where
applicable. - Onset and duration. - Progression. - User-described
severity. - Associated symptoms. - Relevant context. - Optional images
under the correct consent flow.

Patient-reported severity is not a clinical diagnosis. Unknown answers
must remain unknown.

A report-only observation is different from a completed image capture or
confirmed measurement. The UI and Home status must preserve that
distinction.
7.2 Guided capture and image quality
The long-term direction includes a standardized capture workflow: -
Clear camera permission and image-use disclosure. - Guided framing. -
Consistent distance, angle, and lighting where feasible. - Image-quality
checks. - Retake guidance. - Secure, authenticated image retrieval. -
Provenance for any derived measurement.

Standardization matters because inconsistent lighting, angle, distance,
and image quality can create misleading apparent changes.

However, the current repository audit found that the Flutter capture
experience is still primarily file-picker/text guidance rather than a
complete live camera pose-guidance engine. Do not claim real-time face
tracking or a validated capture algorithm unless implemented and tested.
7.3 Measurements
Any image-derived values must be presented as the actual backend
response with: - Metric name and unit. - Algorithm/version. - Quality
status. - Provenance. - Limitations. - Comparability status.

Current backend measurement work includes local image proxies such as
redness chromaticity and texture contrast. These are not validated
clinical measurements and must not be confused with legacy 0--100
hydration/texture/redness scores.

Do not display synthetic measurements as patient results.
7.4 N-of-1 / personal experiment engine
The product supports a scientific direction in which a person's own
baseline and longitudinal response matter more than generic population
averages.

Core concepts: - Baseline. - One clearly defined intervention where the
engine requires isolation. - Frozen experiment configuration. - Product
and routine history. - Adherence records. - Contextual factors. -
Follow-up observations. - Evaluation with coverage and limitations. -
Historical results and revisions.

Important corrections to earlier concept documents: - Do not assume
every experiment must last exactly 28 days. - Do not impose a universal
5-day baseline. - Do not assume a fixed comparison interval. - Do not
automatically pause or alter a clinician-approved treatment. - The
current product decision is that baseline and follow-up timing must be
tied to the specific routine/treatment plan and its authorized
doctor/future validated-AI workflow, case by case. - The comparison
model is not yet built/clinically validated. - The app should prepare
integration-ready boundaries, not invent model output.

A positive association is not proof that an intervention caused
improvement.
7.5 Deterministic ingredient / conflict intelligence
The project has explored a deterministic ingredient-conflict matrix
rather than relying solely on generative AI for chemical compatibility.

This is a potentially useful safety-oriented engine, but: - Rules need
reliable evidence and clinical review. - Ingredient synonyms and
concentrations require careful normalization. - Missing concentrations
remain unknown. - AI must not invent interaction rules. - No product
interaction warning should be marketed as a comprehensive medical safety
guarantee.

OCR / label extraction is a possible future extension, not an assumed
completed feature.
7.6 Safety and escalation
The system must: - Avoid diagnosis and prescription claims. - Recognize
urgent red flags through approved, testable logic. - Stop ordinary
chatbot responses when an urgent condition is identified. - Show clear,
immediate emergency guidance. - Preserve clinician instructions and
review decisions. - Avoid suggesting that a generic doctor-contact
snackbar is a complete care pathway.

The current backend has deterministic Safety logic and
clinician-assistance guards. The Flutter audit found that the standalone
patient Safety presentation and Home integration were incomplete at the
audit checkpoint.
8. AI & Personal Skin Health Model
8.1 Personal Skin Health Model (PSM)
The PSM is a longitudinal evidence model, not simply a classifier or a
chatbot.

It should integrate: - Observations and check-ins. - Capture and
measurements. - Routine and product history. - Experiment history. -
Patient-reported context. - Environmental context where legitimately
available. - Clinician-authored information and visible decisions. -
Safety state. - Unknowns, stale data, and provenance.

The backend has a /personal-skin-model projection (PSM v2) documented
in the repository. The October 10 Flutter audit found no official
Flutter API method/widget/controller for consuming it at that time.
Current integration must be checked against HEAD before assuming this
remains true.
8.2 Existing contextual AI vs future Agent
These are distinct systems and must not be conflated.

Existing contextual assistance: constrained backend assistance that
selects allowed owner-scoped facts and steps, applies deterministic
safety/clinician guards, validates provider configuration, and fails
safely. It is not a general autonomous agent.

Future Agent vision: a proactive contextual companion that can
understand the user's authorized Dermaire history, identify relevant
changes or missing information, suggest next steps, and help prepare
clinician questions.

The future agent may have: - Authorized read capabilities. - Context
retrieval. - Explanation and summarization. - Suggestions. - Explicit
action previews. - User confirmation. - A narrowly allowlisted execution
broker for safe nonclinical operations.

The current backend has bounded Agent session/request/action
infrastructure, including a narrow nonclinical notification-read action.
It does not have genuine model inference enabled.
8.3 Agent authority model
Separate: 1. Read. 2. Understand. 3. Suggest. 4. Request an action. 5.
Execute an explicitly authorized action.

A suggestion is not execution. A clinician request is not a treatment
change. A confirmation does not override medical authorization.

Never: - Diagnose autonomously. - Change treatment. - Override Safety or
clinician instructions. - Invent memory or evidence. - Access another
patient's information. - Execute arbitrary model-generated tools. -
Claim a model response exists when provider inference is unavailable.
8.4 Conversational context and proactive behavior
Long-term product vision: - The agent can use authorized Dermaire data
and relevant conversation context. - It can notice changes or missing
tracking information. - It can gently help a returning user resume their
journey. - It can suggest priorities based on actual state. - It can
prepare a clinician summary.

Constraints: - No complete durable chat history or full conversational
memory should be claimed unless implemented. - No proactive scheduler
should be claimed unless real event triggers and scheduling exist. - A
return after absence must not infer non-adherence or disease progression
from missing data. - Medical decisions remain with the clinician and
user.
9. Product Modules & Scope
The overall architecture is organized around these product areas:
1. Trusted Patient Entry.
2. Structured Observation.
3. Authoritative Home & Safety.
4. Capture, Measurements & Comparison.
5. PSM & Contextual Assistant.
6. Routine & Experiments.
7. Preferences, Notifications & Offline.
8. Doctor Experience.
These are product domains, not a claim that all are fully implemented.
9.1 Home
Home is the authoritative starting point, not just a decorative
dashboard.

Proposed priority order: 1. Urgent Safety. 2. Clinician instructions /
pending review. 3. Uncertain operations or data requiring
reconciliation. 4. Due observations, routine actions, and experiment
tracking. 5. Longitudinal insights and learning.

The server remains the authority for medical and clinical states. A
stale cached view can be shown as stale; it cannot claim current medical
clearance.
9.2 Routine and products
Routine management should include: - Product inventory. - Routine
configuration. - Morning/evening schedule where appropriate. -
Instructions and product references. - Adherence reporting. -
Completed/skipped/unknown distinctions. - History and revisions. -
Product changes and intervention records.

Product ownership and routine use are distinct. Owning a product does
not prove it was used.
9.3 Experiments and outcomes
The user should be able to understand: - What intervention is being
tracked. - What baseline applies. - What was changed and when. - What
adherence evidence exists. - What context was reported. - What follow-up
evidence is comparable. - What the evaluation can and cannot conclude.

Insufficient evidence is a valid outcome.
9.4 Before/After and comparison
This is not an arbitrary saved-image comparison.

It must be linked to an authorized plan/intervention and a valid
baseline/follow-up pair. Baseline and follow-up timing is case-specific
and should be selected through doctor/future validated AI authority.

No universal fixed interval. No automatic "end of routine" schedule. No
invented improvement percentage or comparison score.

The backend has durable comparison job infrastructure and explicit human
review boundaries, but real artifact verification/loading, secure image
transport, model validation, and clinical validation remain blocked.
9.5 Doctor collaboration
Must include: - Authenticated role. - Real patient connection. -
Separate VIEW and EXPORT scopes. - Explicit patient consent. - Grant
expiry and revocation. - Current authorization on every private
read/write. - Clinical notes and review actions. - Patient-visible vs
private clinician content. - Secure messaging. - Follow-up plans. -
Auditability.

A painted QR placeholder or local "connected" flag is not a real
connection.
9.6 Notifications
Distinguish: - Scheduled. - Enqueued. - Provider accepted. - Delivered
to a device. - Read in the application.

These states are not interchangeable.

The backend includes reminder scheduling/outbox infrastructure, but
genuine provider transport and device delivery proof remain blocked. No
push delivery claim should be made.
9.7 Offline
Offline behavior should prioritize safe cached viewing and recoverable
drafts.
- Show freshness.
- Keep account-scoped private cache.
- Clear private cache on logout/account switch/revocation as
  appropriate.
- Preserve original operation identity for uncertain writes.
- Reconcile before retry.
- Never claim an unconfirmed write succeeded or failed.
- No offline medical authorization or autonomous intervention.
10. Technology & System Architecture
10.1 Repository
https://github.com/Hussamwaleed15/Dermaire-Project

Main folders: - app/ --- Flutter client. - backend/ --- Python
backend. - data/ --- project data/assets. - docs/ --- product,
architecture, audit, technical and competition documentation. -
deployment/ --- deployment-related files.

Always inspect the actual current tree before assuming filenames or
module locations.
10.2 Flutter client
Technology: - Flutter / Dart. - Material 3. - ChangeNotifier-based state
management. - Repository boundaries. - Shared ApiService. -
DermaireState composition. - Feature controllers. - Existing app shell
with a six-page IndexedStack at the October 10 audit. - Existing
light/dark theme scaffolding. - Fraunces and Karla font assets.

Direction: - Preserve the existing foundation initially. - Introduce
typed DTOs for Safety, PSM v2, review status, capture/measurement, and
assistance as needed. - Keep repository injection and session/generation
guards. - Split large screens/files incrementally as vertical flows are
implemented. - Do not rewrite state management or introduce a new router
without demonstrated need. - Separate official and tester identities and
environments.

Shared async states should include: loading, empty, fresh,
stale, partial, permissionDenied, unavailable, and
writeUnconfirmed.
10.3 Backend
Technology: - Python. - FastAPI. - SQLAlchemy. - Pydantic schemas. -
PostgreSQL (with SQLite compatibility for bounded tests). - Alembic
migrations. - Azure-hosted deployment.

Backend areas include: - Authentication/session/security. - User profile
and consent. - Safety. - Observations/check-ins. - Capture and image
access. - Measurements. - Context. - Baseline. - PSM. - Assistance and
Agent infrastructure. - Products and product intelligence. -
Routine/adherence. - Experiments/evaluation. - Doctor access, clinical
records and reviews. - Messaging and follow-up plans. -
Notifications/reminders. - Comparison evaluation infrastructure. -
Account deletion and recovery.

Backend logic is authoritative for clinical states, permissions, data
ownership, and durable writes. Flutter must not recreate that logic.
10.4 Azure / cloud
Known project setup and history: - Resource group: dermaire-rg. -
Azure Web App: dermaire-api. - App URL used in deployment work:
dermaire-api.azurewebsites.net. - Azure Communication Services
resources were created for password-reset email work: dermaire-email,
dermaire-communication, and an Azure-managed email domain. - Backend
deployment previously succeeded after dependency correction from
psycopg2-binary to psycopg[binary]. -
EXPOSE_PASSWORD_RESET_TOKEN=true was set during development
troubleshooting; do not assume this is an acceptable production setting.
Verify current configuration and remove unsafe exposure before any
release. - Azure provider registration and email-domain connection work
occurred; successful end-to-end password-reset delivery was not
established in the available context.

Important October 6 Azure rehearsal: - Production was explicitly NOT
READY. - A separate nonproduction PostgreSQL 18 rehearsal and staging
work were performed. - No production deployment, production database
mutation, or production configuration change was authorized by that
report. - Staging had real TLS, PostgreSQL role and restore rehearsals,
deletion journal, monitoring and controlled fault drills. - The report
identified remaining production gates: ownership/least privilege,
adoption and private storage policy, accepted recovery objectives and
retention, verified human alert delivery, startup/capacity budget, and
privacy-compatible rollback. - Do not treat staging evidence as
production certification.
10.5 Data and image privacy
Required principles: - HTTPS. - Authenticated private image endpoints. -
Owner-scoped access. - No public image URLs. - No transferable SAS URL
as an authorization substitute. - Image disclosure before upload. -
EXIF/GPS handling and secure storage. - Retention and deletion
semantics. - Account/session-bound caches. - No PHI in generic push
payloads. - Secrets outside source control, with appropriate secret
management.

Older technical reports contain aspirational claims about AES-256,
ephemeral SAS, on-device feature extraction, Azure Vision, GPT-4o,
Content Safety, Cosmos DB, or other services. Those claims must not be
repeated as current implemented capabilities unless the live source and
deployment evidence prove them. The current audited backend uses
PostgreSQL and has a constrained provider architecture; actual AI
inference and clinical image inference remain blocked.
11. Security, Consent & Data Authority
11.1 Authorization
- Current authenticated account and stored role are authoritative.
- Every private resource must be owner-scoped.
- Clinician access must use the original valid grant.
- VIEW is not EXPORT.
- Revocation and expiry must be enforced server-side.
- A replacement grant must not revive an old grant's authority.
- Every private deep link must be reauthorized.
- No cached content may bypass revoked permission.
11.2 Consent
Keep separate: - Safety acknowledgement. - Image processing consent. -
Clinician VIEW consent. - Clinician EXPORT consent. - Agent
clinician-request routing consent. - Routine reminder consent. - OS
notification permission. - Any future research/data-use consent.

These are not interchangeable.
11.3 Idempotency and uncertain writes
For sensitive writes: - Preserve the original idempotency key. -
Preserve exact normalized payload. - Preserve original
revision/precondition. - Reconcile the original operation after
timeout. - Do not create a new key merely because the response was
lost. - An original committed receipt proves the original SQL
transaction, not current resource state. - unknown is not proof of
rejection or non-execution. - Provider acceptance is not proof of device
delivery.

The backend F8 work qualified important receipt/concurrency paths on
real PostgreSQL. The full product still requires mobile integration and
external-provider/device validation.
12. Design System & Experience Direction
12.1 Brand feeling
Dermaire should feel: - Advanced medical technology. - Premium. - Calm
and intelligent. - Trustworthy. - Human and friendly. - Expressive
without being distracting.

Avoid generic hospital software aesthetics and generic skincare-commerce
styling.
12.2 Approved palette
Light mode - Background: #FAF4EC - Surfaces: #FFFCF8 - Main
text: dark brown / deep burgundy family. - Primary action: #681B22 -
Deep emphasis: #481116

Dark mode - Background: #17191E - Surface: #24272D - Elevated
surface: #2F333B - Main text: #F7F7F9 - Accent: #E8A1B6 with dark
foreground.

Dark mode is not a brown/burgundy inversion of light mode. It uses
deliberate charcoal surfaces and rose accents.
12.3 Typography
- Fraunces for restrained expressive headings.
- Karla for readable body and interface text.
12.4 Language
The application UI is English-only. This is an explicit product
decision. Do not add Arabic UI, RTL localization, Arabic ARB tasks, or a
language selector unless the project owner explicitly changes this
decision.

This does not prohibit backend recognition of Arabic red-flag phrases
where already supported, or Arabic discussion between the project owner
and assistant.
12.5 Navigation
A prominent centered camera action is desired.

The final navigation model remains open. Options discussed include: -
Home / Journey / Routine / Profile with a centered Camera action. - Home
/ Journey / Care / Profile with a centered Camera action. - A smaller
shell with Home / Journey / Profile and contextual routine access.

Do not independently finalize navigation. Validate discoverability and
daily tasks, then get project-owner approval. Preserve the current shell
until an approved replacement is justified.
12.6 Motion
The app should feel alive through meaningful: - Transitions. -
Micro-interactions. - Gesture behavior. - Timeline interactions. -
Charts. - Camera guidance. - Haptics (optional). - Responsive cards and
sheets.

Motion rules: - Never delay urgent guidance. - Never imply an
unconfirmed write succeeded. - Respect reduced-motion settings. - Keep
clinical state readable without animation or color. - Performance must
be validated on actual devices.
13. Current Implementation Status --- Evidence-Based Snapshot
Important date boundary: Repository HEAD is verified at
b995873f2b76e0c37a08f23fbf40322174aba6fe, dated 24 October 2026. The
latest detailed backend status in that commit is F8. The product audit
is dated 10 October 2026. This document is prepared on 12 November 2026,
but there is no verified newer repository commit in this preparation.
Therefore the status below is the latest verified evidence available,
not a claim about uninspected changes after 24 October.
13.1 Flutter findings from the October 10 source audit
The Flutter app has substantial real integration and should not be
treated as a blank prototype.

Bounded working areas included: - Password/session lifecycle. - Profile
CRUD. - Structured report-only check-ins. - Capture upload and
history. - Context read/write. - Baseline authority. - Routine
configuration. - Adherence reporting. - Experiment v2 lifecycle
subset. - Product library and product intelligence panel.

Partial, missing, or contradictory areas included: - Google onboarding
safety acceptance path. - Account/profile hydration and returning-user
flow. - Home safety/clinician/routine priority. - Report-only check-in
vs Home completion semantics. - Real live camera/pose-guidance
experience. - Capture measurement display and history. - PSM v2 Flutter
integration. - Standalone Safety patient presentation. - Clinician
access UI and actual QR generation. - Doctor review/timeline
integration. - Messaging UI. - Notification and offline experience. -
Assistant metadata display and future agent behavior. - Comparison
viewer and plan-linked comparison UI.

Specific source-audit discrepancies: - Welcome copy said photos stay on
device although uploaded images are transmitted/stored. - Capture
history checked a legacy image_sas_url field while backend supplies an
authenticated image endpoint. - Flutter discarded returned measurement
proxies and displayed misleading "no measurements created" copy. -
Report-only check-ins did not advance the legacy confirmed-measurement
baseline, by design of current backend semantics. - The Home completion
metric counted confirmed metric check-ins, not report-only
observations. - The doctor QR screen was a painted placeholder; its
access copy contradicted actual authenticated grant/TTL behavior. -
Revoke behavior cleared local state before confirmed server
completion. - The doctor workspace had a nullable active_experiment
contract defect. - Chat UI discarded richer assistance
provenance/uncertainty/provider metadata.

These findings are dated and must be rechecked before acting.
13.2 Backend F8 status --- 24 October 2026
The backend status document reports: - PostgreSQL 18 gate: 1,148
passed, 0 failures, 0 errors, 0 skipped. - 95 actual PostgreSQL-gated
cases. - Alembic head: 20261024_14. - OpenAPI: 114 paths / 117
schemas. - Compile, drift, diff and security/concurrency checks
passed. - Commit 7706c6a76c1947ecf71b5f1a86bcbde3fe224a41 contains F8
implementation. - Repository HEAD
b995873f2b76e0c37a08f23fbf40322174aba6fe adds F8 final report/handoff
documentation.

Backend status distinctions: - Clinical write/revoke receipts and
important concurrency paths: bounded implementation and
PostgreSQL-tested. - Routine configuration evidence/history and
prospective calendar policy: bounded implementation. - Reminder
scheduling/outbox worker infrastructure: bounded local implementation. -
Clinician request lifecycle and a narrow nonclinical action: bounded
implementation. - Comparison jobs, leases, cancellation, consent and
human review infrastructure: bounded implementation. - Genuine model
inference: BLOCKED. - Validated clinical image model/artifact and
clinical validation: BLOCKED. - Genuine push provider transport and
device delivery proof: BLOCKED. - Production deployment/readiness:
not established by local tests.

The backend report explicitly says local tests do not certify mobile
integration, production deployment, delivery, clinical safety, or
accuracy.
13.3 AI / comparison / push reality
- Existing contextual AI is constrained, not a general agent.
- New Agent model provider is unavailable/disabled; no fabricated
  replies.
- Comparison output is unavailable without verified artifact, secure
  image transport, and clinical validation.
- No diagnosis, numerical improvement, or accuracy claim is permitted
  from synthetic fixtures.
- Push provider is disabled; notification enqueue/provider acceptance
  does not equal device delivery.
- Hosted worker and real device/provider proof remain external gates.
13.4 Azure readiness
The October 6 Azure readiness report says NOT READY for production.
It documents isolated staging and PostgreSQL/restore/monitoring
rehearsals but also explicit remaining production gates. Do not deploy
or mutate production based on that report.
14. Roadmap --- Project-Wide
This roadmap is a strategic sequence, not a promise that every phase is
already started or complete.
M1 --- Trusted Patient Entry, Observe & Authoritative Home
- Correct account/session hydration.
- Server-backed safety acceptance.
- Correct onboarding and Google flow.
- Structured observation.
- Distinguish report-only observation from image capture and confirmed
  metric baseline.
- Integrate Safety and visible clinician status.
- Correct Home authority and freshness.
- Correct image privacy copy.
- Typed models and robust async states.
M2 --- Guided Capture, Measurements & Comparison Readiness
- Real camera experience or honest upload fallback.
- Capture quality and permission states.
- Display actual measurement response and provenance.
- Secure authenticated image access.
- History and non-comparable states.
- Prepare plan-linked comparison UI/state contracts without inventing
  model results.
M3 --- PSM, Understand & Contextual Learning
- Integrate PSM v2.
- Evidence cards with source and freshness.
- Assistant metadata and uncertainty.
- Safe contextual suggestions.
- Clinician decision panel.
- Return-after-absence behavior.
- No autonomous action tools until separately approved.
M4 --- Routine, Products, Adherence & Experiments
- Integrated daily routine experience.
- Product inventory and stable references.
- Adherence with unknown vs skipped distinction.
- Experiment lifecycle and frozen configuration.
- Contextual evidence and evaluation.
- Explain insufficiency and association limitations.
M5 --- Preferences, Notifications & Offline Recovery
- Notification center and preferences.
- Reminder consent and scheduling.
- Device registration only with permission.
- Real push only after provider/device proof.
- Secure cache and draft behavior.
- Operation reconciliation and session cleanup.
M6 --- Doctor Experience
- Authenticated clinician workspace.
- Real patient connection.
- VIEW/EXPORT permissions and consent.
- Clinical timeline, notes and review.
- Messaging and follow-up plans.
- Export/report workflow.
- Revocation/expiry and audit verification.
Cross-cutting workstreams
- Product safety and clinical governance.
- Privacy, security, threat modeling and retention.
- Design system, motion and accessibility.
- Data quality and provenance.
- AI provider/model validation.
- Azure production readiness and operations.
- Imagine Cup story, evidence, demo and judging preparation.
15. Team, Ownership & Collaboration
15.1 Roles
- Project owner: Amr Abdallah --- product direction, final product
  decisions, approval of scope and sequencing.
- Backend/Azure/database/AI model owner: Hussam Waleed.
- Flutter owners: Amr Abdallah and Salma Ahmed.
- Additional Flutter support: Salma Sami when needed.
- Testing: designated testers; tester reports are observations,
  not independent code changes.
The user confirmed the official Imagine Cup team members (four or
fewer). Exact roster details should be verified with the owner before
formal submission.
15.2 Boundaries
When working with Amr on Flutter: - Focus on Flutter. - Report backend
gaps to Hussam. - Do not independently change backend/Azure/database/AI
model. - Do not let testers modify code independently. - Review all
tester reports together and verify against source before changing the
master plan.

When working with Hussam: - Backend, Azure, database, model/provider and
API contracts are his ownership. - Flutter must consume actual contracts
and report gaps clearly.
15.3 Preferred engineering workflow
- Inspect before changing.
- Small real increments in the existing project.
- No unsolicited mockups/prototypes before implementation.
- No large rewrite for visual novelty.
- Provide complete replacement files when substantial file replacement
  is needed, not scattered fragments.
- Run focused tests, full relevant tests, and static analysis.
- Review diffs.
- Commit and push meaningful milestones to the existing GitHub
  repository.
- Keep documentation synchronized.
- Never claim completion without evidence.
- Do not automatically create a new Codex/Work chat or handoff;
  provide a copy-ready prompt in the current conversation unless
  explicitly asked to hand off.
16. Microsoft Imagine Cup 2027
Dermaire is being prepared for Microsoft Imagine Cup 2027.

The project owner emailed Microsoft to clarify eligibility because
Dermaire is not currently a legally registered entity. The owner wants
to wait for Microsoft's reply before making decisions.

Do not assume: - That legal incorporation is required. - That it is not
required. - That the team is eligible or ineligible. - That a particular
entity structure is best.

If Microsoft confirms a legal entity is needed or beneficial, the owner
previously identified establishing the entity as a likely first step,
followed by the other competition requirements and project-readiness
work.

Competition preparation should include: - Eligibility and team rules
confirmed from official Microsoft guidance. - A concise problem
statement. - Clear differentiation from generic AI skin scanners. -
Architecture and responsible-AI explanation. - Evidence of working
implementation vs planned features. - Demonstrable patient journey. -
Privacy/security and clinical limitations. - Technical validation and
measurable results. - Honest cost/scalability/deployment explanation. -
Demo reliability and contingency planning.

Never present blocked AI inference, unvalidated image analysis, unproven
clinical outcomes, or staging-only Azure evidence as production-ready
capabilities.
17. Open Decisions & Explicit Non-Decisions
The following remain open unless the owner later approves a decision: -
Final navigation structure. - Exact Home layout and card hierarchy
beyond authority/safety priorities. - Final product-card styling. -
Routine gestures and any gamification. - Detailed motion timings after
device testing. - Comparison model and validated output. - Plan-specific
baseline/follow-up dates. - Genuine AI model/provider and allowed
capabilities. - Genuine push provider and delivery proof. - Clinical
validation pathway and intended-use claims. - Production Azure readiness
and operational acceptance. - Legal entity and competition eligibility
after Microsoft's response.

Do not convert ideas into approved decisions.
18. Important Historical Documents & Source Map
Repository source of truth:
https://github.com/Hussamwaleed15/Dermaire-Project

Core docs: - docs/COMPREHENSIVE_TECHNICAL_REPORT.md -
docs/DERMAIRE_PATIENT_ARCHITECTURE_ROADMAP_20261010.md -
docs/DERMAIRE_ARCHITECTURE_PRODUCT_AUDIT_20261010.md -
docs/DERMAIRE_AGENT_CAPABILITY_AUDIT_20261010.md -
docs/READINESS_AUDIT.md -
docs/azure-readiness-rehearsal-20261006.md -
docs/contextual-ai-v1.md - backend/docs/EXPANDED_MASTER_STATUS.md -
backend/docs/EXPANDED_FLUTTER_HANDOFF.md -
backend/docs/BACKEND_F8_FINAL_REPORT_AR.md -
backend/docs/BACKEND_F8_FLUTTER_HANDOFF.md

The detailed backend handoff documents include API contracts,
authorization headers, idempotency, operation reconciliation, reminder
semantics, agent requests, comparison evaluation and human review. They
are implementation references, not substitutes for the product vision.
19. Instructions to the New ChatGPT Account
You are now helping the project owner continue Dermaire. Treat this
document as the initial project-wide context, but do not assume it is
the newest code status.

Your first responsibility is to understand the whole project, not to
jump immediately into Flutter tasks.

Follow these rules:
1. Understand the product first. Dermaire is a Longitudinal
   Personal Skin Health System. Do not reduce it to a chatbot or photo
   analyzer.
2. Preserve decisions. English-only app UI; light and dark modes;
   approved palette; safety-first; all skin concerns; longitudinal PSM;
   patient/doctor separation; plan-linked comparison; no automatic
   medical changes.
3. Separate status categories. Always label information as
   approved, implemented, partially implemented, blocked, proposed, or
   unknown.
4. Inspect the repository. If GitHub is connected, inspect the
   current main branch, recent commits, project instructions, latest
   audits and relevant source before proposing code changes.
5. Resolve conflicts by authority. The project owner's explicit
   latest decision overrides old proposals. Current code proves
   implementation, not product approval. Current backend contracts
   prove API behavior, not clinical validation. Old technical reports
   may contain aspirational or superseded claims.
6. Do not invent capabilities. Especially no fake AI inference,
   clinical scores, model accuracy, image improvement percentages, push
   delivery, clinician verification, or production readiness.
7. Respect ownership. Flutter work belongs to Amr/Salma;
   backend/Azure/database/model work belongs to Hussam. Report
   cross-boundary gaps instead of changing another owner's domain.
8. Work incrementally. No unsolicited mockups, no broad rewrite, no
   new repository, no automatic handoff to another chat.
9. Verify. Tests, analyzer, source diff, actual backend contract,
   session/privacy behavior and Git status must support completion
   claims.
10. Ask only when necessary. Use the known context. Do not
    repeatedly ask the owner to explain decisions already documented
    here.
11. Keep a living decision log. When a decision changes, record the
    old decision, new decision, reason, date, and affected modules. Do
    not silently overwrite history.
12. Do not assume Imagine Cup eligibility. Await the official
    Microsoft response before entity/legal decisions.
Recommended first action in the new account
Read this document, then inspect the repository at its current HEAD and
compare it with the status snapshot above. Produce a concise Project
State Reconciliation with: - Current HEAD and date. - New commits
since b995873. - Current Flutter status. - Current backend status. -
Azure/deployment status. - AI/model and comparison status. -
Push/notification status. - Open blockers. - The next best project-wide
priority and why.

Do not start coding until the owner agrees on the immediate objective.
20. Final Project Principle
Dermaire is not a collection of screens and APIs. It is one connected
system that must preserve continuity, evidence, context, user authority,
privacy, and clinical safety over time.

Build the real patient journey, not just the interface. Make every claim
traceable to evidence. Keep uncertainty visible. Let AI assist without
taking clinical authority. Do not confuse a prototype, a passing test
suite, a staging deployment, and a clinically validated product.

The goal is not to make Dermaire look intelligent. The goal is to make
it genuinely useful, trustworthy, and responsible.
