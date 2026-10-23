# CI-speedup execution — PRs green and admitted; GitHub merge queue's merge step is failing platform-side

Work issue: #4691 (PR #4685) and #4696 (PR #4686). Plan: `plan_ci-speedup.md` (landed #4687). Critique + execution log: `plan_ci-speedup-critique.md`.

## State at 2026-10-23T23:00Z (7:00 PM EDT)

- **PR #4685** (check-in window 10→60 min, lease cap 0.5→1 h, messages derived, rulebook + truth-audit catalogue synced): head `66f5def10b7bbcebe5143a434707bf7e8d523c03`, evidence generation 4 published (`refs/db-contracts/4691/4`), all required checks green (the ephemeral RLS contract test flakes on first run — statement timeout — and passes on rerun; two occurrences today), muse APPROVE (round 2, on the pre-refresh head; later commits are main-merges and evidence pairs only), guarded lane admitted it to the merge queue at 22:30Z.
- **PR #4686** (owner ruling §6.30 + promotion-procedure documentation): head `8a528ed3ce0573902a425a8778461a56f1197c01`, evidence generation 2 (`refs/db-contracts/4696/2`), checks green (the two Documents-only contexts fail by design for rulebook files — they are NOT required), admitted once at 21:07Z, dropped by the queue timeout.
- **GitHub's merge queue is broken tonight**: entries batch, group checks pass, then the merge never fires and the 30-minute entry timeout (`check_response_timeout_minutes: 30` in ruleset "main merge queue") silently drops them. Observed on PR #4717 (another session's: batch all-green at 21:44Z, dropped 22:17Z, never merged) and twice on #4685. Queue merges last succeeded 21:25Z (#4697). This is a platform outage, not a repo defect; do NOT admin-merge around it.

## Exact next actions

1. Re-admit each PR when the queue recovers: `gh workflow run guarded-migration-merge.yml --repo popcre/shared-db --ref main -f pull_request=<4685|4686> -f head_sha=<current head>`. If the lane refuses "anchored to a superseded base", run `node scripts/refresh-code-pr-branch.mjs --issue <4691|4696> --pr <4685|4686> --worktree <worktree>` (it refuses on the 13 pre-existing Windows-local historical-test failures — that refusal is safe to override by pushing the implementation head it committed and writing the next evidence generation by hand; follow the gen-4 pattern in the PR history), push, wait CI, re-admit.
2. Queue recovery probe: `gh api "repos/popcre/shared-db/actions/runs?event=merge_group&per_page=3"` shows fresh group runs AND `commits/main` advancing = recovered.
3. After both merge: close issues #4691 and #4696 with the merge SHAs.

## Follow-ups (open, owned by the plan)

- B1: fold production risk into slot 1 — design in `plan_ci-speedup-critique.md` addendum (v2 head-bound assessment schema; prove-production-risk-acceptance gains a pre-merge branch). NOT started.
- Cut 1: lane watchdog auto-dispatch when a required lane run never starts (the 16:24Z conflict-marker outage proved the need; root cause was b8a3b7a34 committing markers into tools-offline-tests.yml — fixed on main by e9b1cb2c9; a YAML-validity guard is still missing).
- Cut 2: dedicated API budget for checks (15-minute quota sleeps).
- New findings from tonight: the 30-minute queue entry timeout is too tight for one-at-a-time batching in busy periods; `rls_public_admin_initplan_contracts.sql` is timing-marginal on the ephemeral runner (two first-run timeout failures, both passed on rerun).

Worktrees: `D:/repos/shared-db-worktrees/zcode-ci-speedup-a1` (#4685), `.../zcode-ci-speedup-b1` (#4686). Posted by ZCode chat unknown on edge-dev.
