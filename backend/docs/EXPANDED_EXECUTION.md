# Expanded backend execution ledger

Current delivered status and complete residual backlog: EXPANDED_MASTER_STATUS.md.
The matrix below is the preimplementation inventory at the stated baseline.

Baseline: canonical origin/main 0702773f664825b90b57c4dda53193f5672d23e0.
User authorization supersedes the former documentary H5 sequencing gate; clinical,
privacy, consent and deployment boundaries remain mandatory. No feature is removed
from scope. OPEN means implementation remains; BLOCKED requires external evidence.

## Dependency DAG and acceptance matrix

| Track | Dependency order | Acceptance / residual state at inventory |
|---|---|---|
| A | existing provisioned doctor + current VIEW grant → explicit messaging enrollment → immutable sends + receipts → follow-up plans | OPEN: persisted pagination/read watermarks, original-grant revocation, account erasure, concurrency, lost responses; typed follow-up CAS, acknowledgment, source links |
| B | explicit preferences/device consent → local inbox/outbox → leased worker → provider | OPEN: quiet hours, retry/dedup/cancel/logout/erasure; BLOCKED actual delivery until credentials and device validation |
| C | explicit owner baseline + authorized plan → consent/revisions → private follow-up → immutable evidence/review | OPEN workflow/history; BLOCKED clinical model inference until validated integrated model |
| D | consented fresh retrieval → durable sessions → preview → user confirmation → authorized broker | OPEN bounded actions, revocation, stale context and injection tests; BLOCKED model execution until configured safe adapter |
| E | existing CAS + transaction boundaries → domain receipts → erase/readback; recorded UTC → explicit wall-time resolution | OPEN PATCH/DELETE/routine/experiment/clinical/grants receipts, full configuration history and doctor snapshot |
| F | each increment → focused + full suite + real PG + seeded migration + compile/diff → normal push | OPEN consolidated contracts M1–M6, separate Amr handoff and final evidence |

Source anchors: app/services/doctor_loop.py authorize locks patient/grant;
app/api/deps.py authenticates current credential/session and stored role;
app/services/account_deletion.py uses durable erasure journal;
app/services/product_attempts.py implements bounded product CREATE only;
app/services/clinical_snapshot.py contains patient-only REPEATABLE READ scope;
docs/FOUNDATION_MASTER_STATUS.md and H1–H4 contracts retain their bounded claims.

Conservative calendar policy: record UTC instant, submitted IANA zone, local wall
time and explicit fold choice. Reject nonexistent/ambiguous times without a valid
explicit choice. Travel never reinterprets an existing UTC due instant. Changes
require a revisioned reschedule. Routine end never schedules a comparison.

Messages are not an emergency service or a clinical decision channel. No edits or
deletes are exposed: immutable content avoids silently changing clinical history.
VIEW grants alone never enroll a patient in messaging. Enrollment binds the
original grant; revocation/expiry blocks both sends and readback, including receipts.
