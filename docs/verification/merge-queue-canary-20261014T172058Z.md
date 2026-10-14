# Merge queue canary (Step 9)

**Issue:** [#2530](https://github.com/popcre/shared-db/issues/2530) Phase C Step 9
**Plan:** `plan_shared_db_popcre_transfer_merge_queue.md` Step 9
**File role:** harmless documents-only canary. This file is the ONLY change in its PR.
**Canary UTC timestamp (filename suffix):** `20261014T172058Z`
**Machine / session:** edge-dev · MiMo chat `ses_ffe5ec4d8a438ffeMsuIzWTbV4`

## Purpose

Prove the native GitHub merge queue lands a non-migration, documents-only pull
request through exactly one green synthetic merge group, with every required
context green on the group SHA, the reviewed head proven an ancestor of the
synthetic commit, no bypass, and GitHub — not the guarded lane's direct path —
performing the merge.

This canary intentionally contains **no code, workflow, configuration, script,
test, migration, or rulebook content**. It does not edit `AGENTS.md`, this plan,
or any other `plan_*.md` (those are rulebooks and require the full exact-head
reviewer path).

## What this file asserts at open time

- It is a canary for merge-queue activation, nothing more.
- It adds one file: `docs/verification/merge-queue-canary-20261014T172058Z.md`.
- It changes no database, no production, no preview, no settings.
- It is admitted through the normal guarded path with its exact head
  (`guarded-migration-merge.yml`), never the web merge button and never `--admin`.

## Evidence (completed after the merge lands)

Values that can only exist after admission and the merge group are recorded in
this section by a tiny follow-up documents-only change to this same file, so the
canary carries its own openable proof. Do not invent them at open time.

| Field | Value |
|---|---|
| PR number | _pending_ |
| PR head SHA | _pending_ |
| Queue ref | _pending_ (`gh-readonly-queue/main/pr-&lt;n&gt;-&lt;base-sha&gt;`) |
| Synthetic group SHA | _pending_ |
| Group base SHA | _pending_ |
| PR head is ancestor of group SHA | _pending_ |
| merge_group workflow run IDs | _pending_ |
| All required contexts green on group SHA (count) | _pending_ (live required set at execution: 14) |
| Merge commit on `main` | _pending_ |
| GitHub performed the merge (not direct path) | _pending_ |
| Source head did not move after enqueue | _pending_ |
| No second PR grouped / concurrency stayed one | _pending_ |
| Post-merge checks + consumer sync | _pending_ |
| Queue-only rollback dry-run target | _pending_ (ruleset `main merge queue` id 25099164 only) |

## Operator runbook (executed with this canary)

1. Fresh worktree from current `origin/main`; add only this file; open the PR.
2. Guarded admission with the exact head; confirm lane reports `queue active`
   (exact approved ruleset only); enqueue with `--match-head-commit`.
3. Observe one `merge_group`; record synthetic SHA, base SHA, PR head, queue ref,
   run IDs; prove one-PR group and `git merge-base --is-ancestor`.
4. All live required contexts plus `Merge queue gate` green on the synthetic SHA;
   `Migration guarded merge authorization` success on the group SHA.
5. Prove GitHub merged (not the direct path): `main` advanced once, head did not
   move, concurrency stayed one, no second PR grouped.
6. Post-merge checks + consumer sync for this note.
7. `configure-merge-queue.mjs --rollback` dry-run only; must name only the
   `main merge queue` ruleset (id 25099164); do not apply.
8. Plan STATUS row 9 is updated in a **separate** rulebook PR after this lands.

Posted by MiMo chat ses_ffe5ec4d8a438ffeMsuIzWTbV4 on edge-dev
