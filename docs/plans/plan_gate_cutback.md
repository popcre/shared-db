# Plan: cut back shared-db merge gates and fix the stuck checks permanently

Handoff backlink: [HANDOFF.d/2026-09-28T2000Z-edge-dev3-claude-gate-cutback-watchdog-plans.md](../../HANDOFF.d/2026-09-28T2000Z-edge-dev3-claude-gate-cutback-watchdog-plans.md)
Companion plan: [plan_stuck_work_watchdog.md](plan_stuck_work_watchdog.md)
Relationship to the operating route: this plan is a concrete input to Step 6 ("trustworthy required-check set") and Step 8 (native merge queue) of [plan_shared_db_workflow_refactor.md](../../plan_shared_db_workflow_refactor.md). It does not replace that plan; whoever executes a step here updates that plan's STATUS row too.

## STATUS — read first

Written 2026-09-28 (EDT); revised the same day after Grok (REVISE) and Qwen (REJECT) plan reviews — see "Review record" at the end. Start at Step 1.

| Step | Outcome | Status | Updated | Evidence |
|---|---|---|---|---|
| 1 | Actions-token API spend per workflow measured and attributed | ⬜ open | 2026-09-28 | — |
| 2 | API-scanning gates share one conditional (ETag) snapshot; spend halved | ⬜ open | 2026-09-28 | — |
| 3 | Quota-failed gates re-run automatically after reset (fail-closed kept) | ⬜ open | 2026-09-28 | — |
| 4 | Agent work contract failures classified; missing-file failures made impossible by tooling | ⬜ open | 2026-09-28 | — |
| 5 | Required-set reduction proposal decided by Albert via refactor Step 6 owner | ⬜ open | 2026-09-28 | — |
| 6 | ai-devops `verify`: #1006 fixed; Windows shards off the per-PR path | ⬜ open | 2026-09-28 | — |
| 7 | Local poller hygiene (secondary) | ⬜ open | 2026-09-28 | — |
| 8 | Re-measure: gate-caused (quota/paperwork) failures < 5% for 7 days | ⬜ open | 2026-09-28 | — |

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
   The investigating session itself hit the limit twice during this survey. **Correction after review:** these gates run on the repository's **Actions installation token** (`GH_TOKEN: ${{ github.token }}`), whose budget is separate from any person's login; `scripts/lib/github-transport.mjs` keys its latch by token identity and lives in the runner's tmpdir. So the consumer is CI itself — ~49 workflows, several paginating every open PR/issue per run (`scripts/lib/open-pr-files.mjs`) — not the local pollers. Local pollers exhaust the *user* token (this session hit that limit too), which starves sessions and `ai-pr-wait`, a separate but real problem. The 14-day totals are not yet split quota-vs-genuine; Step 1 does that split. Gates correctly fail closed on quota (`docs/agents/merge-protocol.md` §5.2-B rule 4); the defect is that nobody re-runs them afterwards.
2. **A quota-failed gate stays red forever.** Failing closed is correct doctrine; what is missing is an automatic re-run after the quota resets. Nobody re-runs (see companion plan).
3. **Agent work contract often fails on missing evidence files (sampled, not yet classified across all 24):** `Enforced mode requires this pull request to change both .agent/work/<issue>/<gen>/contract.json and .../report.json` — PRs missing one of two evidence files. It is 56% red. It is an owner-activated control (#1403, #2591 exemption for prose only; rulebook files keep full treatment) — so the fix is tooling that always writes both files, not weakening it.
4. **Documents-only merge authorization is NOT redundant** (corrected after review): it is the only producer of the required status `Migration guarded merge authorization` on prose-only PRs (`scripts/manage-migration-author-lanes.mjs --authorize-repository-maintenance-status`, context in `scripts/lib/merge-self-context.mjs`), under the coordination mutex. It fails only because of quota. Keep it; fix quota.
5. Seventeen guards never failed in 14 days. That means they do not false-fail — they are not the blocker and are kept. (Intake pointer and Domain ownership are designed to be required; see their headers.)
6. **The required-context mirror may only grow:** `scripts/update-required-checks.mjs` refuses removals; `docs/verification/main-required-status-checks.json` is tool-written; `scripts/check-merge-queue-workflows.test.mjs` fails if coverage shrinks. Required-check authority is owned in-flight by refactor Step 6 (#3361, owner: Codex required-check authority session) and native queue by Step 8 (PR #3567, independent REVISE on #2530). Shrinking the set is an owner decision.

## 7. Rejected approaches

- **Delete all custom gates and rely on review only.** Rejected: collision, lease and destructive-SQL guards protect a database shared by four apps (AGENTS.md §3).
- **Raise quota by adding more tokens/Apps per gate.** Rejected: hides the poller problem, multiplies secrets.
- **Accept reviews bound to earlier heads when only tests changed.** Already refused by owner rule in AGENTS.md §5.0-C; do not reopen.
- **`paths:` filters on required workflows.** Rejected by standing memory "merge gate: never propose paths: filters" (skipped required checks stay pending forever). Use in-job early exit instead.
- **Just re-run failed checks by hand.** That is the status quo that produced idle sessions.

## 8. Design decisions

Locked (2026-09-28, after review):
- **No gate is deleted and none becomes advisory in this plan.** Every blocking gate measured fails for quota or missing-file reasons; fix those causes. Documents-only merge authorization stays (it produces a required status). Agent work contract stays enforced (owner-activated). Domain ownership, Handoff contract, Intake pointer stay required.
- Gates keep failing closed on API unavailability (merge-protocol §5.2-B). Recovery is an automatic re-run with the correct token after reset (Step 3, executed by the companion watchdog).
- Consolidation reduces API spend inside existing workflows, keeping every required context name, the marker guard's `schedule`/`push` legs, and the merge-time re-proofs in `merge-queue-gate.yml` and `guarded-migration-merge.yml`.
- Reducing the 16 required contexts is proposed only, through refactor Step 6's owner (#3361) and Albert; candidate: combine Cross-PR collision + Migration author lease + Orchestrator marker guard into one context once Step 2 has run green 7 days.
Open: whether a separate GitHub App token for gates is needed — decide from Step 1 numbers (if Actions-token spend stays above 70% of budget after Step 2, yes).

## 9. Steps

### Step 1 — Measure Actions-token spend
Add `X-RateLimit-Used`/`remaining` logging to `scripts/lib/github-transport.mjs` (one line per workflow run: `api_spend workflow=<name> used=<n>`), then over 48 h tabulate spend per workflow and split the 14-day failures into quota vs genuine using `gh run view --log-failed` patterns (`rate limit exceeded`, `installation quota low`). Record in `docs/verification/gate-api-spend-<date>.md`.
Gate: file lists each workflow's hourly spend and the quota/genuine split for the five gates.

### Step 2 — One conditional snapshot inside existing workflows
Make collision, lease and marker PR legs read open PRs/issues through `scripts/lib/github-conditional.mjs` (already implements ETag 304 + host single-flight) and a shared per-run snapshot artifact produced by one job and consumed by the others via `needs:`. Keep each job name (= required context) unchanged; keep `orchestrator-marker-guard.yml` `schedule`/`push` legs; keep `merge-queue-gate.yml:147` and `guarded-migration-merge.yml:185,201-202` merge-time calls untouched. Cancelled work guard is offline and is not touched.
Gate: Step 1 logging shows per-PR spend for these gates at least halved; existing tests `scripts/check-merge-queue-workflows.test.mjs`, `migration-author-lease.yml` suite and `Tools offline tests` green.

### Step 3 — Automatic re-run after quota reset
Owned by the companion watchdog (its Step 2): `gh run rerun <run-id> --failed` with a token that has `actions:write` on shared-db, only when the failed log matches the quota patterns exactly, once per head SHA, and only after `rate_limit` shows reset. No `workflow_dispatch` retries (they carry no PR payload and evaluate nothing).
Gate: a quota-failed gate on a live PR goes green with no human re-run.

### Step 4 — Agent work contract: fix the cause of missing files
Classify all 24 failures (Step 1 method). For missing-contract/report failures, make `ai-task-gates` (ai-devops) always write both `.agent/work/<issue>/<gen>/contract.json` and `report.json` on `start`/`check --before pr`, and have the gate's error print the exact command that creates the missing file. Do not widen the #2591 exemption.
Gate: failures of type "contract without report / report without contract" = 0 over 7 days.

### Step 5 — Proposal for a smaller required set
Post the Step 1–4 evidence on #3361 (refactor Step 6) proposing one combined coordination context; Albert decides. Only after approval, change via a tool change to `scripts/update-required-checks.mjs` reviewed under §5.0-C, never a hand-written protection PUT.
Gate: a decision comment on #3361.

### Step 6 — ai-devops `verify`
Fix the classifier/offline shard failures on #1006 from `gh run view --log-failed` (a real test fix). Then move Windows shards to `merge_group` + nightly; PRs run Linux shards.
Gate: #1006 green; median PR `verify` < 10 min.

### Step 7 — Local poller hygiene (user token)
`bin/ai-pr-wait` and `bin/ai-blocker-watch` reuse the same conditional-request approach (port `github-conditional.mjs` semantics) and one poller per PR per host (lock file). Reviewer wrappers do not poll GitHub.
Gate: 10 waiters on 3 PRs spend < 100 user-token requests/hour (`tests/gh-poll-budget.test.mjs`).

### Step 8 — Re-measure
Repeat the section 5 command for 7 days after Step 4. Record in `docs/verification/gate-cutback-remeasure-<date>.md`.
Gate: quota/paperwork failures < 5% of PR runs.

## 10. Tests required
- `tests/gh-poll-budget.test.mjs` (ai-devops): shared cache, ETag 304 path, one-poller lock.
- `scripts/lib/github-conditional.test.mjs` extensions: snapshot reuse across jobs; partial pagination never treated as complete.
- `tests/task-gates-evidence-pair.test.mjs` (ai-devops): `ai-task-gates` always writes both contract and report.
- Existing: `Tools offline tests`, `scripts/check-review-parallelism-brief.mjs`, `scripts/check-exact-head-approval.mjs` stay green.

Adversarial cases (trust boundary = GitHub API responses):

| Input | Hostile case | Test |
|---|---|---|
| API response | 403 rate limit | github-conditional.test "quota → fail closed, marked quota for rerun" |
| API response | partial pagination (page 2 fails) | github-conditional.test "partial snapshot never passes" |
| API response | stale ETag cache after new push | gh-poll-budget.test "head SHA change busts cache" |
| PR body | forged lease claim text | existing lease suite "lease requires ref reservation, not text" stays green |

## 11. Constraints and gotchas
- Never push to `main`; branch + PR + merge queue. Workflow/script changes are code: normal checks, governed review (AGENTS.md §5.0-C), not the docs-only admin merge.
- Branch-protection change is shared infrastructure: independent read-only reviewer APPROVE before running it.
- Never a partial snapshot treated as "no collisions".
- Sign GitHub posts `Posted by Claude chat <id> on <machine>`.
- Times in EDT.

## 12. Access
`gh` authenticated as u2giants with popcre admin. Reading branch protection needs `secrets.SYNC_TOKEN` (the Actions token cannot; run 36186790619). Any new token is stored in 1Password vault `vibe_coding` by title, never pasted. Run `ai-task-gates start --class <class>` first.

## 13. Done, risks, open questions
Done: all 8 STATUS rows cite a PR/run artifact; refactor plan Step 6 row updated; re-measure file committed.
Risks: snapshot sharing bug → collisions slip. Mitigation: merge-time re-proofs untouched; snapshot partial = fail. Rollback: revert the workflow PR.
Open: whether GitHub App quota should be split per repo (decide after Step 1 measurement).

## Self-audit
1. Fresh session can execute? Yes — goal (§1), system (§2), exact files/commands per step (§9), gates per step.
2. Carries background and rejected paths? Yes — §5 measurements with reproduction command, §6 log quotes, §7 rejections including owner-refused ones.
3. Goal clear enough for judgment? Yes — §1 "merged the same hour without a person unsticking it; database safety checks stay".

## Review record (2026-09-28)
Grok (grok-4.6-build) VERDICT: REVISE; Qwen (qwen3.8-max) VERDICT: REJECT. Both found: deleting Documents-only authorization strands a required status; advisory Agent work contract widens an owner exemption; neutral+dispatch retry is not implementable and breaks fail-closed doctrine; merged gate dropped the marker schedule and merge-time re-proofs; required set cannot shrink via the existing tool and collides with #3361/#2530/PR #3567; quota root cause was the Actions token, not local pollers. All incorporated above: no deletions or advisory changes, re-run instead of neutral, consolidation inside existing contexts, shrink only as a proposal to Albert via #3361. Reports: `.ai/reviews/grok-gate-plans-e10415-*.md`, `.ai/reviews/qwen-gate-plans-e10415-*.md` (local, edge-dev3).
