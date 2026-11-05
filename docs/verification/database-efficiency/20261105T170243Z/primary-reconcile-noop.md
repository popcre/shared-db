# Primary reconciliation: preserve search catch-up while avoiding redundant writes

Owner: shared-db #5662, existing application needs u2giants/popdam3#680 and #706.

## Source and custody

Forward version `20261105170243` was reserved with the native atomic reservation helper after prepared version `20261105160717`. This supersedes only the same owner's **unmerged** `20261105094158` proposal. Both actual target ledgers returned zero old-version rows before forwarding. Current preview and production primary-function source, settings, owner and ACLs matched the originally captured pre-adoption baseline exactly; installed prerequisite train versions were 74117,74126 and142040. Target identities and complete raw snapshots remain protected.

The old unmerged filename is replaced on the same owned draft branch; SQL bytes are identical, SHA256 `e2a9b4f1963eb3bbee9f3f9d0213dede0bf0d4d1a05d6622764646581977baa2`. Earlier source/check history remains in Git and PR5663. No applied or canonical historical SQL is modified. The native singleton policy authorizes only the new exact version/hash for preview and production; no batch, transaction stripping or unrelated entry change.

## Preserved behavior

The picker, null handling, signature, return type, security definer, owner, ACLs and function settings remain unchanged. Settings are search_path public, statement_timeout30s and lock_timeout0. Only language changes SQL to PL/pgSQL. Existing callers still receive **visited groups**, not physically changed groups, so unchanged pages do not prematurely end reconciliation.

Exactly four cached primary fields determine whether the group row needs an UPDATE. Changed rows retain the canonical AFTER UPDATE search refresh. Each unchanged visited group explicitly calls the existing canonical search entrypoint once. This retains member/tag/description and master-character-name-only search catch-up. No VA-owned refresh function is edited. The actual business-change clock excludes these cache fields; unchanged full rows retain their timestamps and watermarks.

## Validation

Isolated PostgreSQL17 with actual canonical change-clock/search triggers and current 74126 search-image helpers passed the unchanged contract:25 visited,5 physical group updates,20 identical full-row preimages,25 actual refresh invocations and all25 necessary stale-search repairs. The function-call counter is transaction-local and detects calls even when downstream no-op logic writes nothing. Character-name-only catch-up, null/empty/missing/duplicate input boundaries and unchanged business watermarks pass.

A hidden extra no-op refresh call fails26vs25 despite adding no document write. The old unconditional function fails the5-write assertion. Side-by-side baseline/candidate output is identical across all four selected primary fields and both return25, while row writes fall25to5.

The catalog prerequisite guard fails before replacement on an empty pre-adoption database. Baseline then installs its old routine, and pass2 installs the candidate; the full contract passes. Without that guard, PL/pgSQL can compile before its tables and the later baseline overwrites it. This ordered negative/positive proof preserves the native replay route rather than weakening its tests.

The migration has no dynamic execution or guarded table DDL. Normal derived function catalog verification and the rollback contract are applicable; no empty sidecar or new verifier contract is invented. `derived-from: none` is correct because the routine predates the ledger and no earlier canonical migration defines it.

## Delivery and limits

This is a held source proposal. No shared-preview/production write, original-job control, synthetic production fixture, manual nightly invocation or retagging occurred. Foreign production release pins and all unrelated policy/history are preserved. Root coordinator must review the concrete new source and sequence the older train before any queue/apply action.

The measured claim is **fewer group-row writes**. Production latency improvement is unproved, and downstream no-op refresh work remains independent. Live proof stays open on the same work/application records; first-night completion of the existing original run was already verified separately and is not credited to this unshipped source. Future full-run, failed-receipt and197reread acceptance remain dependent on actual completion.
