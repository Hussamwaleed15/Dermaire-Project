# M3-F4 — Future backend contracts, separate from existing capabilities

Existing: PSM v2, constrained assistance/chat, selected fact provenance, canonical
safety/visible clinician decisions, and separately authorized user routine/experiment/
observation/capture APIs. They do not provide agent execution or durable memory.
No existing endpoint is requested as missing; proposed needs are not JSON/route claims.

Future requirements:
- Durable account-scoped conversation/turn identities, ordered bounded history,
  explicit context inclusion, retention/erasure/restore and no implicit cross-account memory.
- Capability discovery with version/current availability/preconditions; missing capability
  remains unsupported rather than fake empty/success. Provider swaps behind stable contract.
- Purpose/version/scope-specific consent receipts, actor/time/expiry/revoke/current readback;
  local selections and existing safety terms are not expanded-context authorization.
- Bounded owner-authorized context retrieval with source versions/as-of/completeness,
  relevance/freshness limits and image-data minimization, not full app dumps.
- Allowlisted server tool registry and typed exact proposal parameters/evidence/revisions,
  user-confirmation receipt bound to current proposal and backend authorization at execution.
- Actor/owner/role/grant/context/purpose checks on every read/write; AI cannot grant itself
  clinical authority, override urgent safety or silently replace clinician-directed plans.
- Durable request idempotency/key-payload conflict/retention, execution acknowledgement,
  status/result/readback and uncertain-write reconciliation. No speculative POST replay.
- Cancellation/rescheduling/supersession definitions and current versions; cancellation
  UI never asserts a sent write stopped without actual supported backend confirmation.
- Explicit exclusion of diagnosis, prescriptions/treatment changes, doctor-decision
  override and autonomous medical scheduling/actions; define clinical-review requirements.
- Source/model/version/evidence/uncertainty metadata, unknown/error handling and audit
  minimization without sensitive payload/token logs. No fabricated reasoning or accuracy.
- Separately authorized notification/scheduling integration: opt-in/quiet hours/timezone,
  minimal lock-screen payload, dedup/revoke and current-plan revalidation after opening.
- Include all conversations/proposals/receipts/actions/model copies in account erasure,
  purpose retention, deletion journal and restore/privacy policy; never insecure local cache.

Acceptance before enabling adapter: cross-owner/role/revocation/grant denial, unchanged
proposal confirmation, concurrent/superseded/version conflicts, lost acknowledgements,
unknown/failed/uncertain statuses, repeats/idempotency, clinical precedence/excluded
medical operations and erasure/restore. Current F4 defaults stay unavailable until then.
F2 source-manifest/English server prose and F3 future durable chat handoffs remain.
No backend resources/providers/deploy are authorized by this Flutter document.
