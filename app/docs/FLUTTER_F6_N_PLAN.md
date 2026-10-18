# F6-N implementation plan
Baseline: 0acf2aa, clean main; fetch matches remote. Approved native proposal read.
1. Establish full test baseline. Apply reviewed native/dependency patch, harden existing-db/key/fence checks within approved files. Pin SQLCipher engine and verify actual loaded cipher and strict pragmas.
2. Implement namespace-bound transactional disk OperationJournal, lifecycle fence/cleanup and restart access. No production path activation. Isolated injection only; no replay or token persistence.
3. Test real encrypted files, wrong/missing key, corruption, CAS/concurrency, failure-before-send, account/session isolation and original receipt/current-state recovery.
4. Build synthetic iOS entry, execute bridge/engine and terminate/relaunch persistence evidence; static Android validation if SDK absent. Run full regression per meaningful commit; normal push and verify.
Risks: native loader vs system SQLite, fsync support, missing key with existing database, fence interruption, unsupported schema, old receipt vs current state, hardware behavior not proven by simulator. Additional out-of-scope native edits require separate approval. Production activation NOT APPROVED.
