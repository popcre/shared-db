# Shared-db merge queue operation

Issue [#2530](https://github.com/popcre/shared-db/issues/2530) Phase C replaces first-come-first-served
merges with GitHub's native merge queue (earlier investigation: #1435, closed PR #1950 — studied as
design history, never cherry-picked). This is repository maintenance; it changes no database.

## Safety contract

- GitHub builds and merges one pull request at a time: ruleset `main merge queue`, `ALLGREEN`,
  `max_entries_to_build=1`, `max_entries_to_merge=1`, `min_entries_to_merge=1`, zero minimum wait,
  merge method `MERGE`, `check_response_timeout_minutes=30` (justified in Step 8's dry-run evidence
  from current required-check runtimes; the 25-minute preview hold fits inside it).
- The reviewed pull-request head is immutable. The queue tests a separate synthetic commit containing
  that exact head plus current `main`; `.github/workflows/merge-queue-gate.yml` proves the reviewed
  head is an ancestor of the group commit before anything passes.
- Migration PRs enter in ascending reserved-version order: `scripts/merge-queue-contract.mjs` refuses
  a candidate when another open non-draft migration PR starts at an earlier version, and refuses
  GitHub's 3,000-file coverage ceiling rather than judging a truncated file list.
- `guarded-migration-merge.yml` remains the SOLE admission path. It re-proves the exact head, review,
  claims, collisions, required checks and production lock, reads the live queue state under the merge
  lock, and then either merges directly (queue inactive) or enqueues with `--match-head-commit`
  (queue active). It never uses `--admin`. After activation, GitHub is the sole merger.
- After a migration-bearing merge, the next merge group waits until that exact `main` commit carries
  `Post-merge preview rehearsal: success`, posted only by a successful post-merge rehearsal run of
  `.github/workflows/shared-supabase-migrations.yml` (never on failure, never manually).
- **Queue interlock through the mutation** (issue #3421). The preview hold can wait 25 minutes after
  the gate first reads authorization, and a production freeze in that window revokes the PR-head
  status and takes the production lane. A stale pre-wait read must never authorize the merge. The
  `authorize` job (`Queue interlock`) therefore owns the asynchronous mutation, not merely the status
  posting: it acquires the exclusive merge lane, re-reads PR-head authorization and the production
  interlock under that lock (`merge-queue-contract.mjs --recheck-interlock`), posts group-SHA success
  only when both are live and clear, and **holds the lane until GitHub lands the actual merge**.
  Failure after posting revokes the group-SHA status (fail-closed). The `authorize` job is
  intentionally not a required check-run — a required check still running would deadlock the group.
  This does not activate the merge queue.
- Every required context reports on `merge_group`. Checks whose PR-only payload is absent either
  re-resolve the one queued PR through the queue ref (agent work contract, handoff contract) or defer
  their event-specific operation to `Merge queue gate` (cross-PR object collision, migration author
  lease), which performs the equivalent proof itself. `scripts/check-merge-queue-workflows.test.mjs`
  is the machine proof that no required context lacks merge-group coverage.

The queue does not change review strength: the durable reviewer assignment and verdict remain
exact-head evidence governed by AGENTS.md §4. Queue admission continues to require the operator to
supply that exact reviewed head; the queue proves the head did not move.

## Activation sequence (Step 8)

Activation must happen only after the implementation PR is merged and green on `main`:

1. Restore both `Merge queue gate` and `Queue-sensitive checks (aggregate)` with exactly
   one GitHub Actions app `15368` binding each. Preserve every current requirement and producer
   binding plus `strict: false`. The plain `--add` CLI creates unrestricted new contexts and
   is insufficient for this activation. Use the existing `readLive`, `planUnion`, and
   `applyUnion` helpers from `scripts/update-required-checks.mjs`: form the additive plan from
   fresh live settings, set only the two restored queue entries' `app_id` to `15368`, and
   review that exact `strict`/`checks` payload before its narrow required-checks PATCH.
   The retirement artifact's bound14 `recovery` payload is valid only when fresh live settings
   match its12-context `after` snapshot; otherwise form a new producer-preserving additive plan.
   Verify exact live readback with `verifyReadback`, then refresh the informational mirror using
   `scripts/update-required-checks.mjs --refresh-mirror` and create its guarded pull request.
   Keep the native queue inactive until that mirror is merged. On the frozen, independently
   reviewed mirror PR branch, dispatch both `merge-queue-gate.yml` and `pr-guards.yml`,
   supplying the exact mirror PR number as `agent_contract_pr_number` for PR Guards.
   Verify each run's `head_sha` equals the exact reviewed PR head and its successful named
   check is produced by GitHub Actions app `15368`. After both dispatches, require actual
   SUCCESS for all13 non-self newest exact-head app-bound contexts, including every
   dispatch sibling guard, not merely the two queue checks. The fourteenth context,
   `Migration guarded merge authorization`, is produced by the existing protected
   guarded lane after these prerequisites pass. Any sibling failure refuses
   guarded admission; never reuse an older green run or accept skipped. The aggregate dispatch uses `github.sha`
   and waits for the existing Tools/Promotion lane assertions on that same head; ordinary
   PR events do not start aggregate work. A skipped aggregate does not satisfy the protected
   preflight. Wrong-head, foreign-app, pending, failed, or absent results refuse admission.
   Invoke the existing guarded merge after all13 non-self prerequisites succeed. Its
   protected-main preflight re-proves those13 before and under the merge lock; the lane
   then publishes and reads back its fourteenth self-context as SUCCESS before mutation.
   All14 actual required contexts must therefore succeed before mutation; never post
   the self-context manually or infer it from dispatch completion. Protected-main lane
   accounting remains mandatory on both passes. Only after the
   actual14 mirror is on main can activation pass its live-context coverage gate.
2. Run `node scripts/configure-merge-queue.mjs`. Default is a read-only dry run that refuses unless
   the owner is an organization, the repository is public, the immutable repository ID matches the
   transfer baseline artifact, the queue workflow is on `main`, every required context including
   both queue contexts are live and bound to app `15368`, no mutation lane is held, and a migration-bearing main tip already
   carries its exact-SHA rehearsal status. Save the dry-run JSON as evidence.
3. Inspect the proposed payload independently, then re-run with `--apply`. The tool creates (or
   idempotently updates) exactly the ruleset `main merge queue` and verifies every read-back field.
4. Read back the ruleset by ID and the branch protection: all prior contexts plus both queue contexts
   remain required, `strict` remains false, administrator enforcement unchanged.
5. Prove with one documents-only canary PR (Step 9): one synthetic merge group, all required contexts
   green on the group SHA, GitHub — not the guarded lane — performs the merge.

Do not activate the ruleset from the implementation branch: GitHub would request `merge_group`
checks from `main`, where the workflows did not exist yet, and the queue would correctly deadlock.

## Observing the queue

- `gh api repos/popcre/shared-db/rulesets` lists the ruleset; read it back by ID for full rules.
- A queued PR shows `Merge queue gate` and every other required context running on the synthetic
  `gh-readonly-queue/main/pr-<n>-<sha>` ref. Removing a PR from the queue is done from the GitHub UI
  (the PR's merge-queue box) — never by deleting refs or cancelling someone else's group.
- If `Merge queue gate` fails on the preview hold, the preceding migration's exact merge SHA needs
  its post-merge rehearsal: dispatch `shared-supabase-migrations.yml` with `target=preview`,
  `mode=apply`, `merged_preview_source_pr` (or the map form) and `commit_sha` = that merge commit,
  under the existing preview lock. The gate releases the next group only when that exact SHA carries
  the success status.

## Bounded failures

- The gate's preview hold waits 25 minutes (`PREVIEW_HOLD_MAX_SECONDS`), inside the ruleset's
  30-minute check-response timeout. A group that times out is removed by GitHub and can be
  re-queued after the hold clears; nothing is merged partially.
- A failed rehearsal means the next group stays blocked. Recover preview through the existing
  governed procedures; never post the status manually and never bypass with `--admin`.
- If the queue mutation does not land within the `authorize` job's hold budget, the job revokes the
  group-SHA `Migration guarded merge authorization` status and releases the merge lane. Re-run the
  guarded lane after the cause clears; never post the group status manually.

## Queue-only rollback

If the queue itself misbehaves, disable ONLY the new ruleset — never branch protection, required
contexts, or the guarded lane:

1. `node scripts/configure-merge-queue.mjs --rollback` — dry run naming exactly one target: the
   recorded `main merge queue` ruleset ID.
2. `node scripts/configure-merge-queue.mjs --rollback --apply --expect-id <id>` — deletes that one
   ruleset and verifies it is gone.
3. The guarded merge lane's `--queue-mode` read then reports `inactive` and direct guarded merges
   resume unchanged. The `merge_group` trigger support and the additive `Merge queue gate` context
   stay in place. Direct-mode PRs use the two-dispatch exact-head bootstrap above when these
   queue contexts remain required; remove the contexts later
   only through a reviewed settings change if it ever obstructs direct mode.

Rollback never reverses the `popcre` organization transfer; that is a separate owner decision with
its own authorization (plan §13).

## Inactive queue operation (issue #3987)

While the native queue is inactive, the two queue-specific contexts can be retired
from classic required checks after assigned review of the exact recoverable payload.
Ordinary guarded merges retain replacement-run accounting in protected-main
preflight before lock acquisition and again under the lock. The aggregate identity,
registered assertion names, and replacement lanes remain unchanged. The aggregate
runs for merge groups and explicit dispatch; the queue gate retains both events.
Activation refuses until both queue contexts are restored with their exact producer
bindings and fresh committed coverage evidence. The prospective settings artifact
is a proposal, not live readback; the committed mirror is refreshed only after the
reviewed settings change and actual readback.

Stage A source and negative proof are in `scripts/check-required-checks-preflight.mjs`
and its test file: "protected merge preflight preserves exact-once runner lane accounting
after aggregate retirement", "a required registered lane cannot remove the other assertion
from merge accounting", and "all-attempt listing includes queued replacements and
newest-name normalization preserves rerun semantics". Trusted-policy invocation before
and under the merge lock is retained in `guarded-migration-merge.yml`. Positive live
execution on protected commit2d1d103dc96caf9f78b421c78a25a85ed7aa456a is recorded at
https://github.com/popcre/shared-db/issues/3987#issuecomment-6023586049.

The PR Guards dispatch must replay all required siblings as real assertions. Its selected positive `agent_contract_pr_number` is checked by a fresh trusted pull-request GET: the PR must remain open, both repository identities must be `popcre/shared-db`, the base must be `main`, and its exact head must equal the workflow run's `GITHUB_SHA`. Missing, moved, closed, foreign, or unknown identities refuse. Collision accounting uses that selected PR; the handoff assertion reads its validated title and body; Domain ownership runs its normal assertion; Destructive SQL scans the selected checkout against `origin/main`. A bare manual run without the selected PR remains red. All thirteen non-self newest exact-head, app-bound contexts must actually succeed after both dispatches; the guarded lane proves and publishes its fourteenth self-context before mutation. All fourteen must actually succeed before mutation; skipped siblings never authorize restoration.
