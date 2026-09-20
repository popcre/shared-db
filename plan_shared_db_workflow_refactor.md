# Implementation plan — shared-db workflow refactor: remove administrative blockers, keep every database safeguard

**File:** `plan_shared_db_workflow_refactor.md` · **Repo:** `popcre/shared-db` · **Created:** 2026-09-20
**Tracker:** issue #3306 (non-orchestrator, repository-maintenance) · **Status:** PUBLISHED, NOT STARTED

Albert asked on 2026-09-20 for the administrative cost of landing a change in this repository to
come down, without giving up anything that protects the database. This plan separates the two.

**The distinction this whole plan rests on.** A *database safeguard* answers the question "is this
change safe to apply to a real database?" — the SQL guards, the preview apply, the derivation and
catalog-verification declarations, the object-collision locks, the exclusive production lane, the
external review of migrations, branch protection on `main`. **None of these is in scope for
removal, by anything in this document.** An *administrative blocker* answers no such question: it
is queue bookkeeping, a shared file every PR must edit, a wait that nothing is waiting on, a
procedure that contradicts another procedure, a serialization wider than the object it protects.
Those are what this plan removes.

**This plan authorizes nothing by itself.** It is a tracker and an index. Publishing it does not
close #3306. Each step below lands as its own PR under its own issue with its own live proof, and
a successor must explicitly accept ownership of a step before implementing it. No migration object
is claimed here, no database is written here, and this must not be dispatched to the
structure/schema orchestrator — it changes no database shape.

## STATUS

Read this table first. Do not re-derive a step that is recorded as done, and do not start a step
whose predecessor is unmet.

| # | Step | Existing issue | Live status 2026-09-20 | State |
|---|---|---|---|---|
| 1 | **Task evidence collisions** — every PR writes the same two `.agent` files, so every merge conflicts every other open PR | #2708 | OPEN, active today | ⬜ open — **do this first** |
| 2 | **Global audit-artifact contention** — the throughput truth-audit count and digest are one file every concurrent PR must edit | #2832 | OPEN, 2026-09-17 | ⬜ open |
| 3 | **Required-check truth** — a conflict-dirty PR starts no `pull_request` workflows and looks green; agents serialise CI and re-push per finding | #3002 | OPEN, active today | ⬜ open |
| 4 | **Overly broad serialization** — narrow each lock to the object it actually protects; keep the one-at-a-time preview apply, guarded merge and production lane | #3002, #2832 | OPEN | ⬜ open |
| 5 | **Completion and dependency reconciliation** — no sanctioned writer for scope status, no guidance for `--complete-work` | #2824 | OPEN, 2026-09-17 | ⬜ open |
| 6 | **Contradictory procedures** — the same-repo `return_to` loop files a reject back into its own queue forever | #2836 | OPEN, 2026-09-17 | ⬜ open |
| 7 | **Shared-preview coupling** — preview dependency is a wait, not a check; decouple what does not need preview at all | #2596 | OPEN, 2026-09-17 | ⬜ open |
| 8 | **Bounded closeout / live-proof qualification** — qualify a route before spending an expensive gate on it | #2596, #3027 (closed, reference) | OPEN | ⬜ open |
| 9 | **Merge-queue delivery** — finish the already-planned native merge queue rather than building a second one | #2530 | OPEN, 2026-09-18 | ⬜ open — see `plan_shared_db_popcre_transfer_merge_queue.md` |
| 10 | **Measured reviewer-policy decisions** — briefs rather than extra reviewers; one gap per round on small probes | #2923 | OPEN, active today | ⬜ open — **measure before deciding** |
| 11 | **Stale-place rule** — a stale, red or conflicted protected-source PR must not hold the queue forever | #3273 | OPEN, active today | ⬜ open |

Closed work that is a **reference, not work to repeat**: #3199 (self-service additive lane, queue
hygiene, zero-touch wait chain) and #3027 (live acceptance proofs for Steps 1–4, 6, 7), both closed
2026-09-18. Read them before re-proposing anything they already landed.

## Why step 1 comes first

Every merged PR in this repository carries its own `.agent/` evidence pair, and merging any one of
them conflicts every other open PR that carries a pair. Two costs follow, and both were observed
live on 2026-09-17: the treadmill of refreshing a branch purely to restore a file nothing read, and
the failure mode now written into `AGENTS.md` §5.2-A — a conflict-dirty PR starts **no**
`pull_request` workflows at all, so `gh pr checks` looks green while every merge-tree guard
silently never ran. Step 1 removes the cause of both. Until it lands, every other step in this
plan pays that tax on each of its own PRs, so ordering is not a preference here.

## The safeguards that are explicitly NOT in scope

Any successor step that proposes touching one of these is out of scope for this plan and needs its
own owner decision:

1. `scripts/check-sql.sh` and the SQL migration guards.
2. The preview apply and the requirement that a migration works on preview before production.
3. `-- derived-from:` (§5.0-D) and `-- catalog-verification:` (§5.0-E) declarations.
4. Exact-object collision locks and unique migration version reservation.
5. The one-at-a-time preview apply, guarded merge and production promotion lanes.
6. External reviewer draw for migrations and rulebook files (`AGENTS.md`, `CLAUDE.md`,
   `plan_*.md`, skill and agent directories are **not** documents-only — see
   `scripts/lib/documents-only-change.mjs`).
7. Branch protection on `main` (owner ruling §6.7) and the admin bypass staying an emergency
   route, not a working style.
8. The rule that AI sessions are read-only for production unless the owner names the exact
   resource and action.

## Acceptance for the tracker

#3306 closes only when every step above has either a merged implementation with its required live
proof, or an evidence-backed written disposition saying why it will not be done. Final
measurements must preserve safety and must **report insufficient samples as insufficient** rather
than claim an unmeasured improvement — an unproved throughput gain is not a result.

## How a successor picks this up

1. Read this STATUS table, then the named issue for the step you intend to take.
2. Accept ownership explicitly on #3306 and on the step's own issue before writing code.
3. Work in your own worktree from current `origin/main`; declare the task class with
   `ai-task-gates start`.
4. One step per PR. Do not bundle steps, and do not carry an unproved step forward to a later
   session as a batch of leftover proofs.
