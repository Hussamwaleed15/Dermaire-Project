# M3-F2 — Actual contract limitations

Existing assistance/chat/PSM/safety/clinician routes are implemented and recognized.
No backend/provider change was made. Missing transparency: assistance serializes
only selected facts, not internal SourceAvailability/included/truncated/source
manifest or context built_at. Define an additive bounded provenance/coverage/age
contract if complete-context transparency is needed; do not call selected facts
complete patient history. Evidence revisions/as-of remain separate earlier PSM gaps.

Current question_safety_caution message/next steps include an Arabic sentence.
For the English-only app, publish clinically reviewed English-only response copy or
an actual locale contract. Flutter retains authoritative medical prose verbatim;
it does not translate, strip medical instructions or create a competing classifier.

Read-like assistance can invoke providers and operational events; no conversation
or business-action persistence exists. Future idempotency/durable memory/consent
contracts are separate work; client offers one explicit retry, not automatic writes.
