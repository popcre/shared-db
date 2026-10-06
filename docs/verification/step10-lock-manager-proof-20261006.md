# Step 10 lock-manager proof — compatibility matrix and unified production freshness

Date: 2026-10-06
Issue: popcre/shared-db#3781 (Step 10)
Worktree: `.ai/worktrees/step10-locks-mimo` (branch `mimo/3781-step10-locks`)
Contract generation: 5 (`refs/db-contracts/3781/5`)

## What was proven

### 1. Lock-manager compatibility-matrix assertions

`scripts/lib/lanes/exclusive-policy.mjs` owns pure, fail-closed assertions over
the acceptance matrix in `scripts/target-queue-identity.mjs`:

- `assertExclusivePairCompatibility(left, right, plan)` runs
  `evaluatePairCompatibility` and throws `LaneError` on every non-ALLOW
  decision (same role, same target, freeze, shared evidence, lock order).
- `EXCLUSIVE_LOCK_ORDER` is `['merge', 'production', 'preview']`.
  preview / preview-recovery / preview-rehearsal share one exclusive ref
  (`refs/db-coordination/preview`) and map to one pair kind, so they are one
  exclusive lane.
- `compatibilityMatrixCases()` emits the full fixture list the tests walk.

### 2. Unified production freshness

`evaluateProductionFreshness` (in `scripts/target-queue-identity.mjs`) now
classifies drift with `isProductionInertPath` imported from
`scripts/check-main-tip-freshness.mjs` — the single path-classification source
of truth. Substantive = not production-inert. Production-inert drift (Markdown
documentation, `.agent/` evidence pairs, test-only scripts) is fresh and may
reuse a promotion manifest; substantive drift (`.mjs` gate code, `.sql`
migrations, `.yml` workflows, config, `.json` data) never is. An empty
changed-path list on a moved tip still refuses. Exact tip / same SHA is still
fresh + reuseManifest. `classifyMainTip` with `production=true` already called
the same helper; the two gates now share one policy.

### 3. Fake-lock / sandbox live proof

A tiny in-memory io mimicking `EXCLUSIVE_REFS` proves, at lock level:

- **Preview recovery does not postpone approved production.** Holding
  `preview-recovery` occupies `refs/db-coordination/preview`; the production
  ref stays free and `assertExclusiveAcquisitionPolicy('production', …,
  { heldKinds: [{ kind: 'preview-recovery' }] })` allows the acquisition.
  Same for `preview-rehearsal`.
- **Same-target / same-ref races still refuse.** A second create on an occupied
  ref returns false; `preview-recovery` vs `preview` (one ref) is
  `FORBID_SAME_ROLE`.
- **Merge/production freeze and cross-ref interlocks still refuse.** Production
  is refused while the merge ref is held; merge is refused while the production
  ref is held; merge is refused under a live (or unreadable) promotion freeze.
  These interlocks are encoded in `assertExclusiveAcquisitionPolicy` because the
  pure matrix ALLOWs merge+production without freeze when locks are disjoint,
  and the live lock manager is stricter.

## Call-site wiring status

`assertExclusiveAcquisitionPolicy` is exported from
`scripts/lib/lanes/exclusive-policy.mjs` and re-exported from
`scripts/lib/lanes/exclusive-locks.mjs`. Wiring it into the `acquireExclusive`
call sites **waits on contested PRs** that own
`scripts/manage-migration-author-lanes.mjs` and its tests: **#3622, #3666,
#3627, #3636, #3626**. The production exact-current-main-SHA check inside
`acquireExclusive` stays in place until those land.

## Test evidence

```
node --test scripts/target-queue-identity.test.mjs \
  scripts/check-main-tip-freshness.test.mjs \
  scripts/lib/lanes/exclusive-policy.test.mjs
# 96 pass, 0 fail

node --test scripts/lib/exclusive-lease.test.mjs
# 26 pass, 0 fail
```

No file outside the contract `allowed_paths` was changed. Locks, freeze,
exact-head approval and required checks are unweakened.
