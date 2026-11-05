# Proposal: governed concurrent index maintenance in the existing automatic workflow

STATUS: disabled implementation prepared in isolation; not activated, dispatched or production-applied. Owning need: shared-db issue 5616 / PopDAM issue 663. Coordinator retains schema, merge and production decisions. Read the benchmark findings beside this file first.

## 1. Ultimate goal

Keep picture indexing and customer searches progressing while repairing a physically oversized index, without a long table-write lock, lost vectors, weakened access or manual production commands. If a step conflicts with this goal, the goal wins: stop and flag it. This capability is needed only if the synthetic and representative preview benchmark proves the identical-index rebuild worthwhile and a transactional build exceeds the agreed interruption budget.

## 2. Application and ownership

PopDAM and PopSG are internal artwork/style-guide libraries in `u2giants/popdam3`; one desktop GPU poller writes both search corpora to shared Supabase project `qsllyeztdwjgirsysgai`. Canonical database operations and automatic production delivery belong to `popcre/shared-db`. Preview target identity comes from its current protected configuration, never a copied historical literal. Keep the current coordinator and exact index owner recorded on issue 5616. Claim coordination with 4437 and 1966 is required; an expired lease is not a release.

## 3. Trigger

November 4, 2026: a restarted database left the photo poller stalled, subsequently repaired. Current writes still encounter multi-second DataFileRead waits. Old PopSG text vectors were cleared and replaced with image vectors. Current SG HNSW occupies 662 MB for 56,454 non-null vectors, making retained old graph footprint a repair candidate. No rebuild benefit has yet been measured.

## 4. Scope

In: one immutable, exact-index, concurrent REINDEX operation, preview first, through the existing automatic promotion workflow and its existing serialization. Preserve source data, full-precision vector(768), cosine operator class, predicates, security and availability. Existing migration replay remains unchanged.

Out: arbitrary SQL, production console/SSH/psql sessions outside the workflow, VACUUM, index drops, quantization, compute/disk purchases, broad maintenance scheduling, bypassing review findings, and weakening current migrations' atomicity guarantees.

## 5. Existing code and exact gap

At inspected origin/main `32b303998`:

- `.github/workflows/automatic-production-trigger.yml`: existing automatic selector calls `scripts/automatic_promotion_candidates.py`. It discovers migration PRs and dispatches the existing migrations workflow.
- `.github/workflows/shared-supabase-migrations.yml:2125`: last production step re-proves bounded filesystem/ledger, then chooses either normal Supabase CLI push or the atomic exceptional apply runner. Preview has the corresponding branch around line 850.
- `scripts/atomic_migration_apply.py:504`: `build_wrapper` deliberately wraps SQL and ledger insert in BEGIN/COMMIT. Do not alter this tool to support nontransactional work.
- `docs/production-promotion-procedure.md:284`: pinned CLI pipeline rejects CREATE INDEX CONCURRENTLY and REINDEX CONCURRENTLY. Documented out-of-band maintenance is not authority under this task's automatic-only production restriction.
- `scripts/check-pr-object-collisions.mjs:511–545`: CREATE/DROP/ALTER INDEX modeled; REINDEX is not currently a structural-operation handler. `scripts/check-migration-verify-cost.mjs:267` recognizes REINDEX only for cost inspection.
- Existing immutable migration-train and catalog-attestation tools provide patterns for exact-head evidence and dispatch verification. Reuse their primitives rather than creating another loosely validated receipt store.

No separately governed nontransactional maintenance route, manifest policy, recovery receipt or executor was found. Merely removing BEGIN is unsafe and insufficient.

## 6. Root-cause boundaries

SG write function is a single primary-key UPDATE and has no user triggers. SG autovacuum tuning already applied; 1,699 dead heap tuples do not explain physical graph footprint alone. Shared buffers are 512 MB, smaller than either corpus's HNSW. Other live writes and DAM index vacuum compete for IO. IO timing is off, so disk-credit exhaustion is unproven. Rebuild must demonstrate benefit; this proposal is not evidence that it will.

## 7. Rejected approaches

- Raw concurrent SQL in a migration: fails pinned CLI pipeline and ordinary replay.
- Modifying atomic apply to autocommit: breaks the very guarantee that tool exists to preserve.
- A shell command invoked manually against production: violates automatic-only delivery.
- Plain REINDEX or CREATE/swap without a measured lock budget: can stall all table writers.
- Dropping ANN or changing model/precision: reduces or changes search capability and is outside this request.
- Claiming success from process completion only: crash between physical completion and receipt can make a retry ambiguous.

## 8. Locked and open decisions

Locked: fail closed; a single supported operation kind, `reindex-concurrently`; exact index/table identity; existing workflow concurrency group; no arbitrary SQL or maintenance DDL under `supabase/migrations/`; no schema_migrations ledger edit for maintenance; no new database receipt table; source and verification evidence pinned to immutable GitHub objects. Preserve all current production preflight and review-finding checks.

Open for coordinator: whether measured benefit warrants the capability; exact operation budgets; structural claim scope; and whether existing immutable-ref evidence primitives can accommodate maintenance records without weakening their migration contracts. Resolve these in code/tests before enabling an entry. Policy defaults to an empty operation list.

## 9. Ordered implementation

1. **Add manifest validation and policy, initially empty.** New `scripts/nontransactional_index_maintenance.py` and `config/nontransactional-index-maintenance.json`. Accept only a schema-validated descriptor containing operation ID, work issue, merged source PR, source SHA, target, exact schema/table/index names, expected existing catalog-definition digest, required preview proof digest, lock/statement/deadline budgets and fixed `operation: reindex-concurrently`. No SQL text or shell fragments. Quote identifiers through trusted driver APIs. Generated SQL is exactly one top-level REINDEX INDEX CONCURRENTLY statement. Verification: pure unit tests reject every unrecognized field/operation and malformed identifier.
2. **Add structural classification for the manifest.** Extend `scripts/check-pr-object-collisions.mjs` and relevant contract scope validation to derive existing index plus owning table lock scope from the descriptor. Descriptor edits require exact-object custody like a migration; no migration version is reserved merely for a maintenance receipt. Verification: exact-collision tests catch existing claims and refuse an invented object, missing owner table or mismatch with catalog definition.
3. **Add durable receipts using existing immutable GitHub ref primitives.** Namespace separate from migration receipts, pinned to operation ID + exact source commit + target. Before writing, commit an immutable `started` receipt with current index/table OIDs, definition digest, workflow run, session application_name and operation settings. Completion receipt binds the same start plus replacement live index OID, validity/readiness, definition digest, surviving constraints/dependencies, measured duration and postchecks. These are operation receipts, not SQL ledger rows. Verification: immutable-create, wrong-parent, replay and tamper tests.
4. **Implement check/apply/recover.** Reuse existing protected linked-connection/project-ref checks and secret-safe errors. Require supported nontransactional connection mode and actual target proof. Check exact object, operator class, predicate, validity, dependencies, prior receipts and absence of another active operation before committing `started`. Invoke generated SQL once in autocommit; budgets remain server-enforced. Verify identical definition/validity and no owned incomplete shadow indexes before committing completion. On uncertainty: refuse and preserve explicit recovery custody. Verification: offline mocks plus disposable PostgreSQL integration matrix below.
5. **Integrate in the existing automatic workflow, not a new production channel.** Extend existing selector to distinguish pending maintenance manifests from migration PRs and dispatch the same existing workflow under its existing serialized group. Add manifest identity input, mutually exclusive with migration allowlist; validate exact merged source SHA, review findings and preview proof in both validation and immediately-before-write steps. Maintenance branch bypasses only CLI execution because the descriptor is not a migration; it must not bypass any target/evidence/security gates. Existing preview→automatic-production derivation carries immutable maintenance proof. No manifest means no behavior change. Verification: workflow tests prove an ordinary migration follows byte-equivalent existing path and manual/mixed/stale dispatch is refused.
6. **Prove crash-safe recovery before activation.** If a completed concurrent REINDEX replaced the old OID but the completion receipt was not saved, validate against the immutable start and exact new catalog, then record completion without rebuilding again. If still running, refuse a second writer and retain the existing run as owner. If failed before swap, preserve original valid index and identify only operation-owned shadow objects from recorded catalog/OID/definition evidence. Cleanup requires its own descriptor-derived bounded action and tests; never wildcard-drop PostgreSQL `_ccnew`/`_ccold` names. Ambiguous ownership blocks automatically with verbatim evidence. Verification: fault injection at every boundary, including cleanup, must leave search/write capability intact.
7. **Rehearse the exact candidate, then activate only its exact descriptor.** After all code is merged and empty policy verified, coordinator admits the single SG operation using current measured budgets and claims. Preview proof includes concurrent writer and search probes, real cancellation, duplicate-run refusal and process-kill recovery. Automatic production may select it only after these receipts validate. Verify persisted vectors/counts, same search results, continuing writes and reduced write latency/read amplification; post to issue 5616. No independently issued production command.

## 10. Required tests

Add `scripts/test_nontransactional_index_maintenance.py` and a disposable PostgreSQL integration test (existing PostgreSQL 17 harness pattern; pgvector 0.8.0 already installed in fixture). Cover exact supported SQL generation; no transaction wrapper; no credential logging; preview/production identity; post-rebuild definition equality; existing index constraints/dependencies; concurrent writer progress during build; cancellation and rollback/cleanup; stale source/receipts; replay; no arbitrary SQL; wrong target; process death before start, after start, during build, after swap and before completion receipt. Extend automatic-selector, workflow-dispatch and object-collision suites.

Adversarial input | Hostile case | Required named test
---|---|---
Descriptor | SQL-bearing index name | `test_identifier_injection_refused`
Descriptor | Arbitrary SQL or second operation | `test_only_single_fixed_operation_supported`
Target | DSN/project-ref mismatch | `test_target_proof_is_point_of_use`
Source | Unmerged or stale commit | `test_exact_merged_source_required`
Evidence | Forged or wrong-target preview proof | `test_preview_proof_binding_required`
Catalog | Definition/OID changes before apply | `test_catalog_drift_refuses_write`
Receipts | Existing started operation, another live backend | `test_duplicate_writer_refused`
Crash | Successful swap, missing completion | `test_reconcile_success_without_reexecute`
Cleanup | Foreign/ambiguous `_ccnew` object | `test_foreign_shadow_never_dropped`
Workflow | Mixed migration and maintenance inputs | `test_mutually_exclusive_dispatch`
Timeout | Long writer/reader at final swap | `test_bounded_cancel_preserves_original_capability`

Existing atomic migration apply unit/integration tests must remain unchanged and pass, alongside production guard, selector and immutable dispatch/evidence suites. Run meaningful offline suites before PR; actual PostgreSQL/preview drills are required before enabling even one operation.

## 11. Constraints and gotchas

Worktree from current upstream; exact claims before structural edits; no adopted claims. No source rows, licensed paths, secrets, raw authenticated traffic or credentials in artifacts. Every write proves the target immediately beforehand. Existing protected connection path only. Automatic promotion retains finding holds, exact-head evidence and preview checks. Concurrent reindex can wait on transactions and briefly lock during swap; it is not zero-lock. Failed concurrent builds can leave shadow indexes; recover them by exact ownership evidence, never guessed names. No success until original functions still work. Do not mark this complete when a workflow merely installs.

## 12. Access and environment

GitHub CLI is available for repository/issue reads. Canonical production Supabase MCP was proved read-only and aimed at production; it cannot execute preview drills. Coordinator resolves current preview ref and protected database credentials through canonical shared-db tooling/1Password vault `vibe_coding`, using existing project runbook item references. No new credentials, paid access or infrastructure changes are requested. All synthetic tests remain disposable; production stays untouched until the merged automatic route independently passes admission.

## 13. Done, risk, and rollback

Done means empty-default capability merged through normal code process; all offline/real PostgreSQL crash/lock tests pass; exact preview operation and immutable proofs pass; automatic production operation completes; original vector count/model/search/write capabilities remain proven; measured graph-size/IO improvement is real; issue 5616 has signed before/after evidence and ownership is released safely.

If benchmark rejects meaningful graph savings, do not implement/activate a maintenance operation solely to exercise this proposal. If physical rebuild succeeds but latency remains poor, report residual host/cache contention honestly and keep the same issue open. Rollback of an unsuccessful build preserves the original valid index. Rollback after successful identical rebuild needs no model/data rollback; disable only an unstarted policy entry, not customer search. Infrastructure scaling or a different index design remains a separate coordinator business/safety decision.

Self-audit: all thirteen required sections are present; adversarial matrix names tests; no live capability or acceptance is claimed. Outstanding root decisions are explicitly listed; this is an implementation proposal, not a production authorization.

## Disabled implementation prepared for coordinator review

The isolated implementation now exists; no operation is enabled and no DDL was executed by its author. The earlier raw-REINDEX proposal is superseded by a fixed, more recoverable sequence: named identical CREATE INDEX CONCURRENTLY, a <=3-second atomic rename swap, then DROP INDEX CONCURRENTLY of the exact retired OID. The old valid index remains usable throughout the long build. Deterministic names plus immutable started/built/swapped/complete receipts make failed-build cleanup and crash-after-swap reconciliation exact. A current index with matching definition but an OID different from immutable built.new_oid is refused.

Implementation files:

- `scripts/nontransactional_index_maintenance.py`: fixed-table/index state machine, protected session-pooler connection, total/statement/lock budgets, point-of-use gates, receipt binding and catalog proof. No arbitrary SQL, migration file, schema_migrations edit or model change.
- `scripts/index-maintenance-receipt.mjs`: reuses canonical `githubIo` immutable-ref transport and existing exclusive manager. Exact open object claims and protected foreign-claim collisions remain; retired author capacity/lease-clock rules are not reintroduced. Preview maintenance shares `refs/db-coordination/preview`; production takes the existing production ref and retains merge exclusion. Ownership assertions precede each mutation; release uses holder/generation.
- `scripts/automatic_index_maintenance.py`: empty policy is a no-op; otherwise the existing automatic trigger selects preview, then production only from a successful exact maintenance workflow/job receipt. Existing three-attempt bound is retained.
- Existing workflow reuses its 25th `migration_train_ref` input via strict `refs/db-index-maintenance-operations/<operation>/<target>/<exact-main>` immutable dispatch refs; a 26th input would violate GitHub's limit. All ordinary train/migration paths retain their original behavior for non-maintenance refs. Same workflow concurrency and final queue nudge include maintenance. The trigger needs contents:write only to create immutable dispatch receipts.
- `config/nontransactional-index-maintenance.json` is deliberately EMPTY. No activation descriptor, production apply, migration version or credential change is included.

The operation entry's source PR must have authored the identical policy entry at its own merge commit. Current main, automatic Actions actor, native exact claim, protected target ref, finding hold, immutable dispatch binding, preview completion and maintenance job success are checked independently. Receipts bind the operation source merge SHA, policy digest and executor digest. Unrelated main changes can be retried with the same operation if executor bytes are identical. Changing executor bytes or descriptor semantics requires a new operation identity and explicit custody/recovery planning; the implementation never silently replaces an immutable preview receipt.

Offline tests exercise 16 state/fault scenarios, 6 selector/workflow cases, and 11 immutable/native-claim/exclusive-manager cases. Existing atomic apply, automatic queue, train/source guard, target identity and exclusive-policy suites also pass. These are not real-database acceptance. The author added `scripts/test_nontransactional_index_maintenance_postgres.py` with opt-in real concurrency/cancellation/crash drills, but DID NOT EXECUTE them under the no-DDL instruction. Coordinator must run them in a new isolated PostgreSQL database named `index_maintenance_5616_<suffix>` with existing pgvector 0.8.0; the harness refuses production and any nonempty public schema. Its protected connection environment variable is `INDEX_MAINTENANCE_TEST_DSN`.

Before enabling: coordinator/security review, component/object custody, actual disposable PostgreSQL drills, realistic preview latency/lock proof and exact automatic workflow rehearsal remain required. This branch is reviewable code, not delivered production capability or completed issue 5616.
