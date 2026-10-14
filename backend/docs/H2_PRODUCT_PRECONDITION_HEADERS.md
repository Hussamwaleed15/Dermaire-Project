# Product precondition header regression fix

Product PATCH/DELETE reject duplicate If-Match headers with422 before mutation. FastAPI scalar Header extraction could otherwise select one value; ambiguous client revisions are unsupported. Single quoted revision, opt-in protection,412 stale,428 absent protected and owner/business/delete-journal semantics remain. No migration/receipt/response shape change.

Focused:15 passed,7 dependency warnings,2.22s. Final full and PG API/update-delete CAS evidence are recorded in completion ledger. No deployment/Flutter change.
