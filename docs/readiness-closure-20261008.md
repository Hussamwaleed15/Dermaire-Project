# Dermaire readiness closure — 8 October 2026

This is readiness closure only. No production deployment, SQL write, setting/policy change, traffic switch or credential replacement was performed. All Azure mutations in this continuation were an existing nonproduction email verification resend, a temporary staging-scoped metric rule and a staging application restart. No application records/photo fixtures were created.

## Accepted targets and release plan

The user accepted MVP/Imagine Cup startup/full readiness 180 seconds, DB RPO <=5 minutes, end-to-end recovery RTO <=30 minutes and journal retention 42 days, conditional on every recoverable backup/export <=35 days and quarantine <=7 days. Never expire intents or keys while any recoverable copy remains; keys must also outlive retained signed intents. Targets are objectives; the small rehearsal is not a production-scale guarantee. Geo-restore is not certified for the five-minute RPO.

Updated production-release-runbook.md contains the review-only ownership/adoption/TLS/photo/protected-journal sequence and runtime/migrator separation. least-privilege-postgresql.sql now scopes current CRUD grants to 16 audited business tables, makes Alembic metadata SELECT-only and explicitly denies bypass-RLS, runtime inheritance and privileged role membership. Per-object ownership/PUBLIC/inherited/function grants and actual negative-permission smoke remain mandatory release preflight. This SQL template was reviewed, not executed in this continuation; the prior isolated runtime DDL-denial rehearsal remains evidence, not proof of production application of the template.

Staging PostgreSQL management read: version 18, Ready, seven-day backup, geo backup disabled. Historical Azure PITR and signed deletion replay completed in 493.573 seconds, under the accepted RTO. Complete backup/export/restored-target inventory is required before enabling journal expiration; no expiration was enabled. New offline review helpers reject invalid/long horizons and deny expiration on unknown inventory, legal holds, insufficient age or any surviving copy. Replay still verifies all signatures before mutations, covers account/legacy/orphan photos and refuses production CLI targets. Existing tests cover corrupt signature, fail-closed store/key behavior and replay coverage.

## Alert diagnosis and evidence

Native ARM Action Group read showed the email receiver Enabled and group enabled; no subscription action-processing rules were returned. However Azure Portal showed **Pending email verification** for the existing recipient 2022170636@cis.asu.edu.eg. Enabled was not verification proof. Verification was resent to the same user-provided address; the user completed it, and the portal then showed **Verified**. No OTP/password/token was requested or saved to the repository/evidence.

The Azure-native test-notifications API was retried and again returned Conflict / Free subscription not supported on Azure for Students. This restricts that test API; it is not evidence that real-alert notifications are prohibited. Historical staging Blob/provider alert histories confirmed Action Group execution at both Fired and Resolved, but not mailbox delivery. After verification, a real temporary metric rule dermaire-staging-delivery-20261008 monitored Requests only on dermaire-api-staging. It required no production or synthetic application failure. Azure recorded alert 4b3879d0-cb05-484b-8707-5400bd7ef000 Fired at 10:17:21 UTC (13:17:21 Cairo), and ActionsTriggered at 10:17:21.555 UTC. Its condition was then changed to a safe unreachable threshold. Azure recorded Fired -> Resolved at 10:21:57.496 UTC (13:21:57 Cairo), with ActionsTriggered at 10:21:57.639 UTC. Action execution is not actual recipient receipt.

Azure Portal verification establishes the direct cause of pre-verification non-delivery. University filtering, spam/quarantine and downstream email delivery cannot be ruled out until actual receipt is confirmed; native alert history does not expose mailbox receipt or a mail-gateway trace.

References: [Azure Action Groups recipient verification](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups), [notification troubleshooting](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-troubleshoot), [PostgreSQL backup horizon/RPO](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/concepts-backup-restore).

## Validation and changes

- Full backend suite: **640 passed**, 91 deprecation warnings, 85.58 seconds. Includes 11 new retention validation cases plus the prior 629 tests. Initial local checks encountered absent OpenCV and a denied default temporary directory; rerun used an isolated test environment with the project-pinned OpenCV and workspace temporary files. The full rerun had zero failures/errors.
- Live staging restart: **103.312 seconds** from restart request to changed boot ID and complete readiness (DB, photos and journal available), within 180 seconds. Prior stable maximum was 152.484 seconds. No production restart occurred.
- New files: backend/app/core/operational_targets.py, backend/tests/test_operational_targets.py, docs/readiness-closure-20261008.md.
- Updated files: docs/production-release-runbook.md, docs/production-readiness-fixes.md, docs/deletion-journal-restore.md, docs/least-privilege-postgresql.sql.
- No schema migration, application deployment, production config update or lifecycle expiration. Historical rehearsal report preserved.

## Final delivery/cleanup/release state

**NOT READY. Actual Fired/Resolved email delivery remains unproven.** Both native states and both Action Group executions are proven; those are not mailbox receipt. The existing signed-in school mailbox was inspected directly with focused drill-name/project searches and Inbox Focused/Other/Junk checks. The 13:11 welcome-to-action-group message was present, but neither drill alert was found during the observation interval after resolution. No mailbox rules, sender allowlists, university filtering, account security or production settings were changed. An Exchange administrator's transport/quarantine trace is outside the available Azure permissions; university filtering versus downstream alert-email transport remains unresolved. A separately user-supplied alternative reachable recipient/channel is needed for the next end-to-end delivery comparison; no personal contact was guessed.

The temporary notification metric rule was deleted after confirmed resolution; a subsequent GET returned 404. Final staging full readiness returned 200 with database/storage/journal available. No synthetic user/photo/DB fixture was added; backend test fixtures were dropped by session teardown, workspace test temporary files were cleaned, and staging journal intents needed for existing backup replay were preserved. Existing eight alert rules and the now-verified Action Group remain.

Source changes are intended for the same main branch; identify the commit containing this report with git log. Exact commit/push verification is included in the user-facing closure report. No required code/docs work remains at the recipient boundary.

Production rollout needs a separate explicit instruction and the runbook's release-owner preflight: fresh catalog/grant review, protected journal/backup inventory, exact package/settings archive, maintenance adoption and runtime/TLS/photo policy application, then smoke before traffic. Fresh-clone Google Sign-In from a teammate is still a useful separate team check; it is not a blocker for this infrastructure readiness closure.
