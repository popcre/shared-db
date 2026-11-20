---
issue: 5747
status: OPEN
owner: codex/review-fix/6904
summary: Nov 20 residual index audit is complete; obtain fresh PopDAM search performance proof before closing #5747.
kind: handoff
read-when: continuing #5747 after the Nov 20 residual index decision
---
# Handoff: finish assets bloat close-out for #5747

## 0. Business decisions only the owner can make

None currently. The owner has settled that PopDAM search totals remain exact; do not trade exact totals for speed. No business-meaning question is required for the remaining performance measurement or evidence update.

## 1. What this application is

[Shared-db](https://github.com/popcre/shared-db) controls the shared Supabase database used by POP DAM, CRM, PIM and DesignFlow. [PopDAM](https://github.com/u2giants/popdam3) owns the artwork catalogue and its search experience. Issue [#5747](https://github.com/popcre/shared-db/issues/5747) tracks shrinking `public.assets`, preventing wasteful rewrites, keeping search fast, and proving the result.

Start with the [repository instructions](https://github.com/popcre/shared-db/blob/main/AGENTS.md), [document index](https://github.com/popcre/shared-db/blob/main/docs/INDEX.md), [current workflow](https://github.com/popcre/shared-db/blob/main/docs/agents/current-workflow.md), and [worktree and handoff rules](https://github.com/popcre/shared-db/blob/main/docs/agents/worktrees-and-handoffs.md). The active plan is [plan_assets-bloat-permanent-fix.md](https://github.com/popcre/shared-db/blob/review-fix/6904/plan_assets-bloat-permanent-fix.md).

## 2. What we set out to do and why

Resolve the Nov 20 residual index decision and correct its close-out evidence after advisory review #6904 found a six-index arithmetic omission, an unsupported handoff claim, and stale search performance evidence. The decision must account for all 46 indexes; the parent issue must stay open until current search performance is measured and remaining live close-out proof is recorded.

## 3. Current state, verified and delivery

On branch `review-fix/6904` (from `mimo/5747-step3-residual`), the Nov 20 evidence now reports 44 KEEP + 2 out-of-scope + 0 drops = 46. All six residual candidates are KEEP; no schema change or migration is needed. The [decision record](https://github.com/popcre/shared-db/blob/review-fix/6904/docs/verification/assets-bloat-5747/20261120T1633Z/index-decision-closeout.md) now states that search performance was not re-scored on Nov 20. The [plan](https://github.com/popcre/shared-db/blob/review-fix/6904/plan_assets-bloat-permanent-fix.md) marks the index audit done and calls out the score still owed. This handoff was added on that branch; the changes are not yet merged at the time of writing.

Last recorded Search test set result: u2giants/popdam3 run 43355019011 on Nov 12, PopDAM 119/119, p50 1.0 s, p95 2.2 s. Index size later increased from 825 MB on Nov 12 to 841 MB on Nov 20. This dated result does not establish Nov 20 performance.

## 4. What we tried that did not work

No fresh Search test set run was made in the review-fixer sandbox, which has no network access. Reusing the Nov 12 score as current evidence would be unsupported because the indexes grew after that run. No fresh score or live close-out proof is claimed.

## 5. Root causes and key findings

- The Nov 18 count was 38 KEEP + 2 out-of-scope + 6 residual = 46. Nov 20 resolves all six residuals to KEEP, so the correct result is 44 KEEP + 2 out-of-scope = 46. See the [Nov 20 decision](https://github.com/popcre/shared-db/blob/review-fix/6904/docs/verification/assets-bloat-5747/20261120T1633Z/index-decision-closeout.md) and [Nov 18 close-out](https://github.com/popcre/shared-db/blob/main/docs/verification/assets-bloat-5747/20261118T1411Z/index-recheck-closeout.md).
- Five residual candidates have refreshed reader evidence; `idx_assets_compat_audit` gained 260 scans. None qualifies for removal.
- The previous close-out claimed search performance MET using Nov 12 evidence, despite Nov 20 index growth. Re-score before calling the §13 performance condition met.

## 6. Exact next steps

1. In a session with network access, follow the existing PopDAM Search test-set workflow referenced by [the plan](https://github.com/popcre/shared-db/blob/review-fix/6904/plan_assets-bloat-permanent-fix.md); capture the new run identifier, pass count, typical time, and broad-search time. Success: the current test set and broad search satisfy §13 without changing exact totals.
2. Update the [Nov 20 decision record](https://github.com/popcre/shared-db/blob/review-fix/6904/docs/verification/assets-bloat-5747/20261120T1633Z/index-decision-closeout.md) and [plan STATUS](https://github.com/popcre/shared-db/blob/review-fix/6904/plan_assets-bloat-permanent-fix.md) with the run evidence and accurate §13 verdict. Success: no stale score is described as current and each close-out row has dated evidence.
3. Recheck remaining §13 live criteria and record their proof on [issue #5747](https://github.com/popcre/shared-db/issues/5747). Close only after live proof is complete. Success: the issue has evidence for every required criterion and is closed through its normal owner workflow.

## 7. Constraints and gotchas in force

No production writes, manual SQL, schema change, or migration is part of this remaining work. Keep exact totals. Do not duplicate #5610's shared-pair audit for `idx_assets_tags` and `idx_assets_full_text_search`. A successful Nov 12 score is historical evidence only; do not treat a newer index-size reading as a search score. Review findings are advisory and do not block delivery.

## 8. Access and environment

The review-fixer sandbox was offline and did not verify PopDAM CLI, GitHub, or database access. The existing plan names the PopDAM repository and established test-set evidence. Secrets, if needed by the established workflow, belong in the `vibe_coding` 1Password vault; never place values in files, output, or chat. Do not seek access by asking the owner to click, type, or create credentials.

## 9. Open questions and risks

- 2026-11-20: current search latency and unchanged pass count remain unverified after index growth. Obtain the fresh score before marking performance MET.
- 2026-11-20: #5747 remains open until current performance and remaining §13 live proof are recorded. No new issue is needed for this evidence gap.
