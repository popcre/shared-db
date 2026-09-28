# Plan: stuck-work watchdog, and whether GitHub fits a many-agent workflow

Handoff backlink: [HANDOFF.d/2026-09-28T2000Z-edge-dev3-claude-gate-cutback-watchdog-plans.md](../../HANDOFF.d/2026-09-28T2000Z-edge-dev3-claude-gate-cutback-watchdog-plans.md)
Companion plan: [plan_gate_cutback.md](plan_gate_cutback.md) (do its Step 1–2 first; a watchdog that re-runs quota-starved checks would only burn more quota).

## STATUS — read first

Written 2026-09-28 (EDT). Start at Step 1.

| Step | Outcome | Status | Updated | Evidence |
|---|---|---|---|---|
| 1 | Stuck-PR detector runs every 15 min and writes a report | ⬜ open | 2026-09-28 | — |
| 2 | Automatic re-run of infrastructure-failed checks | ⬜ open | 2026-09-28 | — |
| 3 | Fixer dispatch for real failures with no owner activity | ⬜ open | 2026-09-28 | — |
| 4 | Albert notified once per stuck item, in plain English | ⬜ open | 2026-09-28 | — |
| 5 | Local session side: waiters exit and register instead of polling | ⬜ open | 2026-09-28 | — |
| 6 | 7-day proof: no PR blocked > 2 h without an owner action | ⬜ open | 2026-09-28 | — |

## 1. Ultimate goal

Nothing Albert asked for sits silently stuck. **Within 30 minutes of a PR or session going stuck, something either fixes it, hands it to a named fixer, or tells Albert in one plain sentence what is blocked and on whom.** If a step conflicts with this goal, the goal wins — stop and flag it.

## 2. System

Same as the companion plan §2: `popcre/shared-db` (shared database contracts, 49 workflows, merge queue), `popcre/ai-devops` (session tooling: `ai-pr-wait`, `ai-blocker-watch`, `ai-task-gates`, `ai-review-pool`, reviewer wrappers). AI sessions (Claude, Codex, MiMo, others) on edge-dev/edge-dev2/edge-dev3 and Windows open PRs and are expected to merge them themselves.

## 3. Trigger

2026-09-28: 5+ sessions idle "waiting"; PRs #3567, #3673, #3620 (shared-db) and #1006 (ai-devops) red for hours; 31 background waiters. Each session ended its turn "waiting" and nothing woke anyone to fix the red check.

## 4. Scope

In: detection of stuck PRs in popcre/shared-db and popcre/ai-devops; automatic retry of infrastructure failures; fixer dispatch; owner notification.
NOT in: changing which checks are required (companion plan); reviewer rotation; production or database actions — the watchdog never merges structural PRs, applies migrations, or bypasses a gate.

## 5. Does anything notice stuck work today? — Answer: partially, and nothing clears or reassigns

Existing scheduled workflows in shared-db (read their headers in `.github/workflows/`):

| Workflow | Cadence | What it does | Clears / reassigns? |
|---|---|---|---|
| `orchestrator-no-progress-alarm.yml` | every 30 min | Comments on the orchestrator marker when an orchestrator-owned outcome has no stage change for 120 min | No — comment only, orchestrator outcomes only, not ordinary PRs |
| `reviewer-start-watch.yml` | every 5 min | Checks reviewer relay liveness | No — reviewer starts only |
| `author-lane-abandonment-audit.yml` | hourly | Flags expired author lanes with work queued behind | Report only |
| `queue-hygiene-report.yml` | daily | Unlabelled issues, expired leases, aging work | Report only |
| `handoff-stale-report.yml` | weekly | HANDOFF.d files whose issue closed | Report only |

Local tools: `ai-blocker-watch wait` wakes the *same* session when a condition clears; if that session is dead or the condition is a red check that never clears by itself, nothing happens. `ai-pr-wait` polls one PR inside a turn. **No component looks across all open PRs for "red + nobody acting" and does anything about it.** That is the gap.

## 6. Root cause

Ownership of a red check is implicit (the session that pushed it). Sessions end turns, crash, or wait on each other; red checks caused by infrastructure (quota, runner loss) never clear by themselves; alarms that exist only comment in places no session is watching, and nobody tells Albert.

## 7. Rejected approaches

- **More local pollers per session.** Rejected: they are what exhausts the API quota (companion plan §6.1).
- **Auto-merge by the watchdog.** Rejected: merge authority stays with the governed review + merge queue; the watchdog only re-runs, dispatches, and notifies.
- **Paging Albert for every red check.** Rejected: he is not a programmer; notify only when automation could not resolve within 60 min.
- **Extending the orchestrator no-progress alarm to all PRs.** Rejected: owner ruling §0.0-C keeps monitoring out of orchestrator scope.

## 8. Design decisions

Locked:
- Definition of **stuck**: open, non-draft PR where (a) a required check is failing or the PR is BLOCKED/ejected from queue, and (b) no push, comment or review from any actor for ≥ 45 min. Draft PRs older than 3 days with no activity are "abandoned" (report only).
- Home: a new scheduled workflow in `popcre/ai-devops` (`.github/workflows/stuck-work-watchdog.yml`, cron `*/15`), because it covers both repos and is tooling, not database shape. One GraphQL query per repo per run (≤ 10 API points).
- Actions, in order: (1) infrastructure failure (log matches rate limit / runner lost / 5xx) → re-run failed jobs once per head SHA; (2) otherwise, after 45 min idle → dispatch a fixer (Codex or Claude background task via the existing `codex-handoff` route or a GitHub issue labelled `stuck-fixer` that a scheduled agent picks up), assigning by comment `Owner: <agent> since <EDT time>`; (3) after 60 more min unresolved → notify Albert.
- Notification channel: one GitHub issue `Stuck work — <date>` per day in ai-devops, assigned to u2giants, updated in place (no email spam). Plain English, one line per item: "PR #3567 blocked 3 h on the merge-queue check; fixer Codex dispatched 2:10 PM EDT; no progress."
Open: whether Albert also wants a phone push (ntfy/Pushover) — default off; decide by asking him once in the Step 4 PR.

## 9. Steps

### Step 1 — Detector
`scripts/stuck-work/detect.mjs` (ai-devops): GraphQL `search(query:"repo:X is:pr is:open -is:draft")` with `statusCheckRollup`, `mergeStateStatus`, `updatedAt`, latest commit date, last comment date. Output `stuck-report.json` artifact and a job summary table.
Gate: fixture test with PR #3567-shaped data classifies it stuck; a green PR and a 10-min-old red PR are not.

### Step 2 — Auto re-run of infrastructure failures
For each failed check, fetch the failed step log tail (1 call), match patterns (`API rate limit exceeded`, `quota`, `The runner has received a shutdown`, `HTTP 5\d\d`). If matched and no re-run yet for this head SHA (tracked via a hidden PR comment marker `<!-- watchdog-rerun:SHA -->`), `gh run rerun --failed`. Skip if quota remaining < 500 (wait for reset).
Gate: fixture of today's four quota-failure logs → re-run; a real test failure log → no re-run.

### Step 3 — Fixer dispatch
If still red after re-run, or failure is real, and idle ≥ 45 min: open/refresh issue labelled `stuck-fixer` with PR link, failing check, log excerpt (≤ 20 lines, secrets-scrubbed), and a self-contained brief ("make this PR's required checks green without weakening any gate; never push to main"). Comment on the PR `Owner: stuck-fixer #<issue> since <EDT>`. The fixer is whatever scheduled agent route the toolkit owns (implementer picks the existing one; do not build a new agent runner). If the PR author session resumes and pushes, the watchdog stands down (activity resets the clock).
Gate: dry-run mode on live repos lists exactly the currently-stuck PRs; one real dispatch fixes a seeded red PR in a sandbox repo.

### Step 4 — Notify Albert
Daily issue updated in place; only items stuck > 105 min (45 + 60) with no successful fixer progress. Each line: what, since when (EDT), who holds it, what happens next.
Gate: screenshot of the issue with a seeded item.

### Step 5 — Local side
`ai-pr-wait`: after 10 min, stop polling, register with `ai-blocker-watch` (existing rule #723) and exit; the watchdog is the backstop if the session never returns. Remove per-session background reviewer loops that outlive their session (kill on session end via pidfile).
Gate: `ps` count of waiter processes on a host with 5 sessions ≤ 5.

### Step 6 — Proof
Seven days of `stuck-report.json` artifacts show no PR stuck > 120 min without an `Owner:` comment or Albert notice. Record in `tests/verification/stuck-watchdog-7day-<date>.md` (ai-devops).

## 10. Tests
- `tests/stuck-work/detect.test.mjs`: stuck / not-stuck / draft-abandoned / queue-ejected cases.
- `tests/stuck-work/classify-failure.test.mjs`: infrastructure vs real, using real log fixtures from runs of 2026-09-28.
- `tests/stuck-work/rerun-once.test.mjs`: second run on same SHA does not re-run again.

Adversarial cases (untrusted input = PR bodies, comments, logs):

| Input | Hostile case | Test |
|---|---|---|
| PR comment | forged `watchdog-rerun` marker from a non-bot author | rerun-once.test "marker only trusted from the workflow bot" |
| Log excerpt | contains a token | detect.test "excerpt passes secret scrubber" |
| PR body | prompt-injection text in the fixer brief | fixer brief quotes PR body as data inside a fenced block; test "brief never inlines body as instruction" |
| Check name | a check named like a required one from a fork | classify-failure.test "only required contexts from branch rules count" |

## 11. Constraints
Watchdog never merges, never force-pushes, never edits gates, never touches production/database. Uses the Actions token (read + actions:write + issues:write). Sign posts `Posted by stuck-work-watchdog (ai-devops)`. Times in EDT. Code changes go through normal checks and governed review.

## 12. Access
`gh` as u2giants (popcre admin). No new secrets for Steps 1–4; fixer dispatch reuses whatever credentials the chosen agent route already holds (1Password vault `vibe_coding`, by title only).

## 13. Done / risks
Done: six STATUS rows cite artifacts; Albert sees the daily stuck issue.
Risks: re-run loops burning quota (mitigated: once per SHA, quota floor); fixer fights the original session (mitigated: activity resets, `Owner:` comment). Rollback: disable the workflow.

## 14. Is GitHub the right fit for this many-agent workflow? — Recommendation

Options considered:
- **Keep GitHub PRs + Actions + ~16 custom gate checks (today).** Custom gates re-implement coordination (leases, collisions, markers) by each scanning the whole API; that is what exhausts the quota and turns coordination into red checks nobody owns.
- **Graphite (stacked PRs + its merge queue).** Better stacking UX, but the problem is not stacking; it adds a vendor and still runs the same checks.
- **Buildkite.** Faster/cheaper runners, fixes Windows shard time only; does not address ownership or coordination.
- **Linear / a task queue as the source of work.** Good for assignment, but duplicates GitHub Issues, which already hold the queue and orchestrator markers.
- **Trunk-based with a single integrator agent.** One agent owns landing: sessions push branches, the integrator batches, runs checks, fixes or bounces. Solves "nobody owns red checks" directly, but a single agent is a single point of failure and a bottleneck for four apps.
- **GitHub native merge queue with few checks + watchdog.** Keep GitHub (the whole toolkit, sync, rulesets and history are built on it), cut required checks to about nine, move coordination into one snapshot gate, and let the queue serialize landing; the watchdog supplies the missing owner.

**Recommendation: stay on GitHub, but use it plainly — native merge queue, about nine required checks (companion plan §8), one coordination gate, and this watchdog as the owner of stuck work.** It is the smallest change that removes today's actual failure causes (quota-starved gates, no owner for red checks) without a migration. Revisit a single integrator agent only if, after the 7-day proof, PRs still wait more than two hours on each other.

## Self-audit
1. Fresh session can execute? Yes — definitions (§8), files and gates per step (§9), tests named (§10).
2. Background and rejections carried? Yes — §5 inventory of existing partial alarms, §7 rejections, §14 alternatives.
3. Goal clear? Yes — §1: within 30 min something fixes, reassigns, or tells Albert.
