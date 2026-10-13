# M5-F4 — request recovery and session isolation (COMPLETED scoped increment)

Starting main/origin/main dc434f739884eb52c930e9d48eb60d690565d8f7.
Inspected ApiService transport, Home/clinical/PSM/capture/account/context,
product/routine/experiment controllers, route/session guards and M1–M4 tests.
Existing camera/PSM failure states, clinical freshness/priority, observation
uncertainty and Home no-stale-fact policies retained. No persistent medical cache,
plaintext token, image storage, AI transcript or offline mutation queue added.

Real gaps fixed:
- Routine/experiment GET refresh and product list load no longer start duplicate
  concurrent reads. Repeated refresh calls are ignored while the current read is
  running; explicit subsequent refresh remains possible. No background retry loop.
  Home's deliberate explicit refresh supersession is retained, not replaced.
- Same-session previous routine/experiment/product data is marked stale during a
  read and after failure. Track last confirmed read time separately from dataset
  as-of/clinical clearance; timestamps/errors clear on session invalidation.
- RequestFailure preserves HTTP 403/429/5xx distinction in the M4 resource gateway,
  and maps Timeout/DNS/socket/transport/invalid/unknown failures to safe static
  messages. No device network interface is considered backend reachability.
  No URL/token/server body/exception details are copied to patient feedback/logs.
- Session transport checks authenticated response headers before consuming bodies.
  Current 401 invalidates immediately even with a stalled body. A second check
  after body consumption still rejects account changes during streaming.
- Logout responses never invalidate a newly authenticated session, including
  reused tokens and delayed logout dispatch. Logout already clears local authority
  before its server request; a failed server revocation never restores authority.

Recovery is explicit supported GET only. Failed writes stay failed/uncertain;
GET recovery does not clear routine/experiment uncertain keys or product create
uncertainty. No automatic POST/PATCH/upload/consent/doctor/Agent replay. No success
from network restoration, no fabricated adherence/check-in/measurement, no retry
of a previous-account callback, no navigation into a stale authenticated route.
Idle expiry/current 401/logout clear account state. Old 401 cannot clear account B;
revoked consent and disposal reject late reads. Remaining absence of server attempt
receipts, atomic revision and durable idempotency is in the Hussam handoff.

31 new isolated tests: safe error classification and HTTP states; eight actual
routine failure→GET recovery contracts; concurrent refresh bursts for routine,
experiments/products; uncertain adherence/no replay; logout/account switch/reused
B token/current+old401/revocation/disposal; old logout401; 401 header with a never
consumed body. Production-host assertion and global test HTTP denial preserved.
Full baseline suites retain Home, PSM, guided camera, comparisons, consent,
products, experiments, clinical priority and accessibility/motion regressions.
Validation: analyzer clean; full **1145 tests passed** (1114 preserved +
31 new). Existing generic routine failure assertion now accepts the refined
static error explanation; failed/success and previous-data assertions retained.
F5 adds reusable UI feedback.

Limitations: no durable offline read after app restart, no network detector/auto
reconnect observer, no always-online claim, no automatic retry/backoff, no
exactly-once guarantee. Manual 429 feedback asks the patient to wait; no guessed
server cooldown is manufactured. Platform/device/native QA was not run.
