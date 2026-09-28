# Plan: cut back shared-db merge gates and fix the stuck checks permanently

Handoff backlink: [HANDOFF.d/2026-09-28T2000Z-edge-dev3-claude-gate-cutback-watchdog-plans.md](../../HANDOFF.d/2026-09-28T2000Z-edge-dev3-claude-gate-cutback-watchdog-plans.md)
Companion plan: [plan_stuck_work_watchdog.md](plan_stuck_work_watchdog.md)
Relationship to the operating route: this plan is a concrete input to Step 6 ("trustworthy required-check set") and Step 8 (native merge queue) of [plan_shared_db_workflow_refactor.md](../../plan_shared_db_workflow_refactor.md). It does not replace that plan; whoever executes a step here updates that plan's STATUS row too.

## STATUS — read first

Written 2026-09-28 (EDT). Start at Step 1.

| Step | Outcome | Status | Updated | Evidence |
|---|---|---|---|---|
| 1 | GitHub API quota no longer exhausted by local pollers | ⬜ open | 2026-09-28 | — |
| 2 | Quota-starved gates report "retry", not "fail", and retry themselves | ⬜ open | 2026-09-28 | — |
| 3 | Four API-scanning gates merged into one job with one snapshot | ⬜ open | 2026-09-28 | — |
| 4 | Required-check list cut from 16 to the set in section 8 | ⬜ open | 2026-09-28 | — |
| 5 | Documents-only merge authorization removed as a separate gate | ⬜ open | 2026-09-28 | — |
| 6 | Agent work contract made advisory for non-structural PRs | ⬜ open | 2026-09-28 | — |
| 7 | ai-devops `verify` Windows shards off the per-PR path | ⬜ open | 2026-09-28 | — |
| 8 | Re-measure: gate-caused failure rate below 5% for 7 days | ⬜ open | 2026-09-28 | — |

## 1. Ultimate goal

Albert has five or more AI sessions that sit idle "waiting" on pull requests that cannot merge. The goal is simple: **an AI session that finishes correct work gets it merged the same hour, without a person or another session having to unstick it.** Safety checks that protect the shared database stay; checks that mostly fail for reasons unrelated to the change go away or stop blocking. If a step here conflicts with this goal, the goal wins — stop and flag it on the tracker.

## 2. What this system is

- `popcre/shared-db`: the single source of truth for the shared Supabase database used by CRM, DAM, PM/PIM and DesignFlow. Every schema change lands here via branch + PR + merge queue. Workflows live in `.github/workflows/` (49 files). Required checks on `main` come from branch protection (`gh api repos/popcre/shared-db/branches/main/protection`).
- `popcre/ai-devops`: the shared AI toolkit (`bin/ai-pr-wait`, `bin/ai-blocker-watch`, `bin/ai-task-gates`, `bin/ai-review-pool`, reviewer wrappers). Its `main` uses rulesets ("main: pull request + merge queue"), not classic protection. Its single big CI workflow is `verify` (Linux + long Windows shards).
- Sessions run on edge-dev, edge-dev2, edge-dev3 and Windows machines, all sharing one GitHub App installation / user token quota of 5,000 requests per hour.

## 3. What triggered this work

Snapshot 2026-09-28 afternoon EDT: 31 background reviewer/waiter processes on one host (64 matching `ai-pr-wait|ai-blocker|*review` processes counted by `ps` on edge-dev3 at 4 PM EDT); shared-db PRs #3567, #3673, #3620 BLOCKED on "Documents-only merge authorization", "Cross-PR object collision", "Migration author lease", "Orchestrator marker guard"; ai-devops #1006 failing classifier/offline shards. No one owned clearing them.

## 4. Scope

In: required-check list of shared-db; the five failing gate workflows; quota consumption by local waiters; ai-devops `verify` PR path.
NOT in this plan: reviewer rotation membership; exact-head approval semantics (AGENTS.md §5.0-C refuses widening them — unchanged); production promotion workflows; any database schema; the watchdog (companion plan).

## 5. Current state (measured 2026-09-28)

Command used (reproduce it): `gh run list -R popcre/shared-db --created ">=2026-09-14" -L 3000 --json workflowName,conclusion,event` filtered to PR / merge_group events, grouped by workflow.

| Workflow (shared-db) | Failed / runs, 14 days | Required? |
|---|---|---|
| Agent work contract | 24 / 43 | yes |
| Documents-only merge authorization | 23 / 51 | no (but blocks docs PRs by design) |
| Cross-PR Object Collision | 17 / 43 | yes |
| Orchestrator Marker Guard | 14 / 42 | yes |
| Migration Author Lease | 13 / 44 | yes |
| Queue-Sensitive Checks Aggregate | 3 / 44 | yes |
| Tools Offline Tests | 3 / 43 | yes |
| 17 other PR workflows (Cancelled Work Guard, Domain Ownership, Handoff Contract, Intake Pointer, Destructive Analysis, Public Data Venue, PII guard, etc.) | 0 failures each | many yes |

ai-devops: `verify` 25 / 204 failed; "Reviewer membership drift" 4 / 10.

Required contexts on shared-db `main` (16): SQL migration guards; supabase/tests against an ephemeral database; Cross-PR object collision; Destructive SQL outside migrations; Migration guarded merge authorization; Merge queue gate; Agent work contract; Cancelled work guard; Domain ownership; Handoff contract; Intake pointer guard; Migration author lease; Orchestrator marker guard; Promotion contract tests (offline); Tools offline tests; Queue-sensitive checks (aggregate).

## 6. Key findings and root cause

1. **Four of the five blocking gates are not failing on the change — they fail because the GitHub API quota is empty.** Sampled failed logs (`gh run view <id> --log-failed`, runs of 2026-09-28 18:43–18:49 UTC):
   - Documents-only merge authorization: `REFUSED: GitHub command failed: GitHub API rate limit exceeded (host-wide latch...)`.
   - Cross-PR object collision: `installation quota low: the GitHub API refused the quota probe itself`.
   - Orchestrator marker guard: `UNKNOWN: gh api --paginate .../issues?state=open failed: API rate limit exceeded`.
   - Migration author lease: `REFUSED: GitHub read failed: gh: API rate limit exceeded for installation`.
   The investigating session itself hit the limit twice during this survey. The quota is burned by the dozens of local `ai-pr-wait` / reviewer / blocker-watch processes all polling, plus each gate independently paginating every open PR and issue.
2. **Gates treat "could not ask GitHub" as "the change is bad".** They exit 1/2 (red) instead of neutral + retry, so a PR stays red until someone pushes or re-runs — and nobody does (see companion plan).
3. **Agent work contract fails on paperwork, not substance:** `Enforced mode requires this pull request to change both .agent/work/<issue>/<gen>/contract.json and .../report.json` — PRs missing one of two evidence files. It is 56% red, the worst gate, and proves nothing about database safety.
4. **Documents-only merge authorization duplicates the global rule** that docs-only PRs merge with `gh pr merge --squash --admin`; it adds a mutex and API re-proof that fails under quota pressure.
5. Seventeen required/PR guards never failed in 14 days. Zero failures does not prove uselessness, but each one costs a runner and API calls on every PR.

## 7. Rejected approaches

- **Delete all custom gates and rely on review only.** Rejected: collision, lease and destructive-SQL guards protect a database shared by four apps (AGENTS.md §3).
- **Raise quota by adding more tokens/Apps per gate.** Rejected: hides the poller problem, multiplies secrets.
- **Accept reviews bound to earlier heads when only tests changed.** Already refused by owner rule in AGENTS.md §5.0-C; do not reopen.
- **`paths:` filters on required workflows.** Rejected by standing memory "merge gate: never propose paths: filters" (skipped required checks stay pending forever). Use in-job early exit instead.
- **Just re-run failed checks by hand.** That is the status quo that produced idle sessions.

## 8. Design decisions

Locked (2026-09-28, this plan):
- Target required set for shared-db `main` (9): SQL migration guards; supabase/tests against an ephemeral database; Destructive SQL outside migrations; Migration guarded merge authorization; Merge queue gate; **Shared-db coordination gate** (new, merges Cross-PR collision + Migration author lease + Orchestrator marker guard + Cancelled work guard); Promotion contract tests (offline); Tools offline tests; Queue-sensitive checks (aggregate).
- Become advisory (run, comment, never block): Agent work contract (for PRs touching no `supabase/migrations/**`), Domain ownership, Handoff contract, Intake pointer guard.
- Deleted: Documents-only merge authorization (its job is done by the docs-only admin-merge rule plus Merge queue gate).
- API-unavailable is never a red result: gates exit neutral with a `retry-after` and re-dispatch themselves once quota resets.
Open (implementer judgment): whether Queue-sensitive aggregate can absorb Promotion contract tests; decide by whether both run in under 5 minutes combined.

## 9. Steps

### Step 1 — Stop local pollers burning the quota (ai-devops)
Change `bin/ai-pr-wait` and `bin/ai-blocker-watch` to share one per-host cache (`~/.cache/ai-devops/gh-poll/<repo>-<pr>.json`, 60 s TTL, file-locked) and to use conditional requests (`If-None-Match` ETags return 304 and do not count against quota). Cap one poller per PR per host (lock file keyed by PR). Reviewer wrappers must not poll GitHub at all during a review.
Gate: with 10 waiters on 3 PRs, `gh api rate_limit --jq .resources.core.used` rises by < 100 per hour (test script `tests/gh-poll-budget.test.mjs` with a stubbed `gh`).

### Step 2 — Quota-aware gate outcome (shared-db)
In each API-reading gate script (`scripts/` entrypoints called by `pr-object-collision.yml`, `migration-author-lease.yml`, `orchestrator-marker-guard.yml`), map rate-limit / 5xx errors to exit code 78 → workflow step sets conclusion neutral via a check-run and schedules `gh workflow run` retry at the reset time (one retry job, `retry-on-quota` composite action in `.github/actions/`). Merge queue treats neutral as not-yet-passed, so safety is unchanged; but the check re-runs itself.
Gate: unit test injecting a 403 rate-limit response yields "retry scheduled", not failure; live: one PR survives a forced quota trip and goes green with no human re-run.

### Step 3 — One coordination gate, one snapshot
New workflow `shared-db-coordination-gate.yml` gathers the open-PR file list and open-issue list **once** (two paginated calls), writes `snapshot.json`, and runs the collision, lease, marker and cancelled-work checks as functions over that snapshot. Delete the four separate workflows after it has run green in parallel for 3 days.
Gate: per-PR API calls for these four checks drop from ~4×pages to 2×pages (log line `api_calls=`); decisions identical on the replay corpus (`scripts/throughput-guard` fixtures).

### Step 4 — Apply the required-check list
Update branch protection to the 9 contexts in section 8 through the repository's governed route (branch-protection config file if present per Step 6 of the refactor plan; otherwise an issue with the exact `gh api` call reviewed by an independent reviewer — production-infrastructure rule). Also update `docs/agents/merge-protocol.md` §5 check list.
Gate: `gh api repos/popcre/shared-db/branches/main/protection --jq '.required_status_checks.contexts|length'` = 9.

### Step 5 — Remove Documents-only merge authorization
Delete `.github/workflows/documents-only-merge-authorization.yml` and its scripts; keep `documents-fast-ci.yml`. Update references (`grep -rn "Documents-only merge authorization"`).
Gate: a docs-only PR merges via `gh pr merge --squash --admin` with no red check.

### Step 6 — Agent work contract advisory for non-structural PRs
In `agent-work-contract.yml`, if no file under `supabase/migrations/**` changed, post the finding as a PR comment and exit 0. Structural PRs stay enforced.
Gate: its 14-day failure rate on non-migration PRs is 0 blocked merges.

### Step 7 — ai-devops `verify`
Split Windows shards into a merge_group-only and nightly job; PRs run Linux shards only. Fix the classifier/offline shard failures seen on #1006 first (read `gh run view --log-failed` on its latest run) — that is a real test fix, not a skip.
Gate: median PR `verify` time < 10 min; #1006 green.

### Step 8 — Re-measure
Re-run the section 5 command for the 7 days after Step 6. Record in `docs/verification/gate-cutback-remeasure-<date>.md`.
Gate: gate-caused failures (quota / paperwork) < 5% of PR runs.

## 10. Tests required
- `tests/gh-poll-budget.test.mjs` (ai-devops): shared cache, ETag 304 path, one-poller lock.
- `scripts/coordination-gate.test.mjs` (shared-db): collision, lease, marker, cancelled cases each positive and negative; rate-limit → retry.
- Existing: `Tools offline tests`, `scripts/check-review-parallelism-brief.mjs`, `scripts/check-exact-head-approval.mjs` stay green.

Adversarial cases (trust boundary = GitHub API responses):

| Input | Hostile case | Test |
|---|---|---|
| API response | 403 rate limit | coordination-gate.test "quota → retry, not fail" |
| API response | partial pagination (page 2 fails) | "partial snapshot → retry, never pass" |
| API response | stale ETag cache after new push | gh-poll-budget.test "head SHA change busts cache" |
| PR body | forged lease claim text | coordination-gate.test "lease requires ref reservation, not text" |

## 11. Constraints and gotchas
- Never push to `main`; branch + PR + merge queue. Workflow/script changes are code: normal checks, governed review (AGENTS.md §5.0-C), not the docs-only admin merge.
- Branch-protection change is shared infrastructure: independent read-only reviewer APPROVE before running it.
- Never a partial snapshot treated as "no collisions".
- Sign GitHub posts `Posted by Claude chat <id> on <machine>`.
- Times in EDT.

## 12. Access
`gh` authenticated as u2giants with popcre admin. No secrets needed beyond the existing Actions `GITHUB_TOKEN`/App token. Run `ai-task-gates start --class <class>` first.

## 13. Done, risks, open questions
Done: all 8 STATUS rows cite a PR/run artifact; refactor plan Step 6 row updated; re-measure file committed.
Risks: merged coordination gate has a bug → collisions slip. Mitigation: 3-day parallel run with decision diff before deleting old workflows. Rollback: restore protection contexts from section 5 list.
Open: whether GitHub App quota should be split per repo (decide after Step 1 measurement).

## Self-audit
1. Fresh session can execute? Yes — goal (§1), system (§2), exact files/commands per step (§9), gates per step.
2. Carries background and rejected paths? Yes — §5 measurements with reproduction command, §6 log quotes, §7 rejections including owner-refused ones.
3. Goal clear enough for judgment? Yes — §1 "merged the same hour without a person unsticking it; database safety checks stay".
