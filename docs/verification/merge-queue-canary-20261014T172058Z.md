# Merge queue canary (Step 9) — BLOCKED, queue rolled back

**Issue:** [#2530](https://github.com/popcre/shared-db/issues/2530) Phase C Step 9
**Work item:** [#4300](https://github.com/popcre/shared-db/issues/4300)
**Plan:** `plan_shared_db_popcre_transfer_merge_queue.md` Step 9 / Step 8.6
**File role:** harmless documents-only canary. This file is the ONLY change in its PR.
**Canary UTC timestamp (filename suffix):** `20261014T172058Z`
**Machine / session:** edge-dev · MiMo chat `ses_ffe5ec4d8a438ffeMsuIzWTbV4`
**Outcome:** **BLOCKED** — required workflows did not start on `merge_group`.
  Step 8.6 rollback applied: ruleset `main merge queue` id **25099164** deleted.
  Queue mode read-back: `inactive`. Direct guarded path restored.

## Purpose

Prove the native GitHub merge queue lands a non-migration, documents-only pull
request through exactly one green synthetic merge group, with every required
context green on the group SHA, the reviewed head proven an ancestor of the
synthetic commit, no bypass, and GitHub — not the guarded lane's direct path —
performing the merge.

This canary intentionally contains **no code, workflow, configuration, script,
test, migration, or rulebook content**. It does not edit `AGENTS.md`, this plan,
or any other `plan_*.md`.

## What this file asserts at open time

- It is a canary for merge-queue activation, nothing more.
- It adds one file: `docs/verification/merge-queue-canary-20261014T172058Z.md`.
- It changes no database, no production, no preview, no settings.
- It is admitted through the normal guarded path with its exact head
  (`guarded-migration-merge.yml`), never the web merge button and never `--admin`.

## Evidence — run 2026-10-14 (all times EST / UTC noted)

### Open-time identity

| Field | Value |
|---|---|
| PR number | [#4298](https://github.com/popcre/shared-db/pull/4298) |
| PR head SHA | `1a58862681646e99fef2d57e137844f6f48e0b1e` |
| Work issue (closes) | [#4300](https://github.com/popcre/shared-db/issues/4300) (`Closes #4300`) |
| Guarded admission run | [38609734593](https://github.com/popcre/shared-db/actions/runs/38609734593) (success) |
| First guarded attempt | [38608151542](https://github.com/popcre/shared-db/actions/runs/38608151542) — refused `trusted signed attribution missing` (nonclosing binding; fixed by closing #4300) |

### Queue admission (worked)

| Field | Value |
|---|---|
| Queue mode read at admission | `active` |
| Enqueue verb | `gh pr merge 4298 --merge --match-head-commit 1a58862681646e99fef2d57e137844f6f48e0b1e` |
| Enqueued at | 2026-10-14T17:51:12Z (2:51 PM EDT) |
| Queue ref | `gh-readonly-queue/main/pr-4298-9595a63fcc0c616687d858b0eef1b3864a9d265e` |
| Synthetic group SHA | `7932b3bc3b44574cc488d6e52e11e5582d96efef` |
| Group base SHA (main) | `9595a63fcc0c616687d858b0eef1b3864a9d265e` |
| Group parents | `9595a63fc` (base) + `1a588626` (PR head) |
| PR head is ancestor of group | YES (second parent of synthetic merge commit) |
| Solo / one-PR group | YES (`solo: false`, single entry, position 1) |
| `Migration guarded merge authorization` on PR head | `success` |

### Failure — required workflows never started on `merge_group`

| Check | Result |
|---|---|
| Workflow runs with `head_sha=7932b3bc…` | **0** (repeated over 18 minutes, 17:51→18:09 UTC) |
| Workflow runs with `event=merge_group` since enqueue | **0** (only historical 2026-09-28 runs remain) |
| Check-runs on synthetic SHA | **0** |
| Combined status on synthetic SHA | `pending`, 0 statuses |
| Queue entry state | `AWAITING_CHECKS` until rollback |
| check-response-timeout | 30 min (would eject ~18:21 UTC) |
| PR-head required contexts (14) | all green before enqueue |
| Required workflows' `on.merge_group.types` | all `[checks_requested]` (verified on main) |
| Same workflows on merge_group, 2026-09-28 | DID run (112 historical merge_group runs) |

This is exactly plan Step 8.6's "a required workflow cannot start on `merge_group`"
criterion. Diagnosis ruled out: missing merge_group triggers, branch filters,
Actions disabled, empty required set, missing queue ref, missing synthetic
commit, ancestor failure, second PR grouped, and a healthy queue.

### Rollback (Step 8.6) — applied

| Field | Value |
|---|---|
| Dry-run | `Would DELETE exactly one ruleset: main merge queue (ID 25099164)` |
| Applied | `ROLLED BACK: deleted only ruleset main merge queue (ID 25099164)` |
| Rulesets after | `[]` |
| Required contexts after | 14 intact, `strict: false` unchanged |
| Queue mode after | `inactive` |
| Direct guarded path | restored (lane reports inactive) |

### Not done (blocked by the above)

- All 14 contexts green on the synthetic SHA — **no** (none started)
- GitHub performed the merge — **no** (PR #4298 still open)
- `main` advanced — **no**
- Post-merge checks / consumer sync — not reached
- Plan STATUS row 9 — remains open (separate rulebook PR after a green canary)

### Re-run conditions

A successor canary may reuse this same PR/branch once a re-activated queue
actually starts `merge_group` workflows on the synthetic SHA. Do not invent a
different canary shape. Do not mark `Post-merge preview rehearsal` by hand.

Posted by MiMo chat ses_ffe5ec4d8a438ffeMsuIzWTbV4 on edge-dev
