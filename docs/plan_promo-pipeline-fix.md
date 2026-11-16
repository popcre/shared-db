# Implementation Plan: Fix the shared-db production promotion pipeline jam

## STATUS

| Step | State | Evidence |
|---|---|---|
| 1. Add early-exit guard to `automatic-production-trigger.yml` | ⬜ open | |
| 2. Make the selector skip without dispatching when lane is busy | ⬜ open | |
| 3. Verify: promotion run completes and dispatches next migration | ⬜ open | |
| 4. Verify: designflow-backend#408 migrations reach production | ⬜ open | |
| 5. Live proof on sandbox (screenshots + issue checkoff) | ⬜ open | |

A fresh session starts at **Step 1**.

---

## Part 1 — Why

### 1. The ultimate goal

Merged migrations in `popcre/shared-db` must reach production automatically within a reasonable time (ideally under 30 minutes of merge). Today the promotion pipeline is jammed: the selector either times out or its runs get cancelled before they start, so no migration has reached production in over 24 hours. This blocks every downstream consumer — DesignFlow, CRM, DAM — from getting schema changes. The immediate unblock is: migrations `20261115132055` and `20261116120000` (Disney property-suggestion, issue designflow-backend#408) must reach production so the sandbox live proof can complete.

**If a step conflicts with this goal, the goal wins — stop and flag it.**

### 2. What this application is

`popcre/shared-db` is the canonical repository for POP Creations' shared Supabase database structure. It holds timestamped SQL migrations, contract tests, and tooling. CRM, DAM, PM/PIM, and DesignFlow PLM all read the same tables.

- **Repo:** `popcre/shared-db` on GitHub
- **Default branch:** `main` (branch-protected, merge queue)
- **Production DB:** Supabase project `qsllyeztdwjgirsysgai`, pooler `aws-1-us-east-1.pooler.supabase.com:6543`
- **Key workflows:**
  - `automatic-production-trigger.yml` — the selector that picks the next migration PR and dispatches its promotion
  - `shared-supabase-migrations.yml` — the migration apply workflow (preview and production)
  - `no-progress-alarm.yml` — alerts on promotion-lane stalls

### 3. What triggered this work

On 2026-11-15, PR #6275 (Disney property-suggestion crosswalk) and PR #6370 (review fix) merged to `main`. Their migrations (`20261115132055`, `20261116120000`) have never reached production. Investigation over the following 24 hours revealed:

- The promotion selector (`scripts/automatic_promotion_candidates.py`) takes ~8 minutes to run (processes ~1000 production ledger versions and scans every merged migration PR via GitHub API).
- The trigger workflow has `timeout-minutes: 10` (fixed to 30 in PR #6489, merged 2026-11-16 1:20 PM EST). But this was not the only problem.
- **Root cause:** The workflow's concurrency group `automatic-production-trigger` (with `cancel-in-progress: false`) is supposed to queue runs. But runs are being **cancelled before any job executes** — `gh run view` shows `conclusion: cancelled` with zero jobs. Every trigger in a 30-minute window was cancelled this way. The automatic triggers fire frequently (push to main with migration paths, workflow_run completion, repository_dispatch `production-queue-nudge`, hourly cron), and GitHub cancels the queued runs instead of letting them wait.
- Issue #6352 tracks 4+ stuck PRs (merged 38–70 hours, not live), all "failed 3 automatic attempts." The selector correctly passes over exhausted PRs, but the runs that should dispatch the next candidate never execute.

### 4. Scope

**In scope:**
- `.github/workflows/automatic-production-trigger.yml` — fix the concurrency/cancellation problem
- `scripts/automatic_promotion_candidates.py` — add a cheap early-exit guard (if needed)
- Verification that the promotion queue drains and designflow-backend#408 migrations reach production
- Step 5 live proof for designflow-backend#408 (sandbox screenshots + STATUS table checkoff)

**NOT in this plan:**
- The migration-version backdating race (separate plan on shared-db issue #6423)
- The `--future-minutes` allocator flag (same issue #6423)
- Optimizing the selector's API call patterns (nice-to-have; the timeout increase to 30 min is sufficient once runs actually execute)
- Batching independent migrations in parallel (future improvement; serial lane is safe)
- Fixing the 4 exhausted PRs tracked on #6352 (they need individual repair; the pipeline fix lets later PRs pass them)

---

## Part 2 — What we already know

### 5. Current state of the code

- **`.github/workflows/automatic-production-trigger.yml`** (44 lines): triggers on push to main (`paths: supabase/migrations/**`), `workflow_run` completion of `Shared Supabase Migrations`, `repository_dispatch` type `production-queue-nudge`, and hourly cron (`23 * * * *`). Has `concurrency: group: automatic-production-trigger, cancel-in-progress: false`. Job `trigger` has `timeout-minutes: 30` (updated from 10 in PR #6489). Steps: (1) `automatic_index_maintenance.py`, (2) `write-production-ledger.mjs`, (3) `automatic_promotion_candidates.py`.
- **`scripts/automatic_promotion_candidates.py`** (800+ lines): the selector. Has the #6352 fix (skip PRs already in production ledger). Passes over held/exhausted/dependency-waiting PRs. Returns `dispatch`, `wait`, or `idle`. The `wait` return fires when any migration workflow run is not `"completed"` (line 426–427).
- **`scripts/write-production-ledger.mjs`**: reads production `supabase_migrations.schema_migrations` and writes a JSON file of applied versions. Works (986 versions as of 2026-11-16).
- **`supabase/migrations/20261115132055_dcp_property_mg06_crosswalk_and_suggestion.sql`**: creates `plm.dcp_property_mg06_crosswalk` table and `plm.suggested_property_for_sku(text)` function. Merged to main. NOT on production.
- **`supabase/migrations/20261116120000_fix_property_suggestion_view_and_grants.sql`**: fix-forward (consumer view, exact-only filter, grants). Merged to main. NOT on production.
- **DesignFlow code** (backend endpoint, Item Detail UI): on `sandbox-albert`, auto-deployed. Waiting on the DB function to exist on production.

### 6. Key findings and root cause

**Primary root cause — concurrency group cancellation:**
- `automatic-production-trigger.yml` has `concurrency: group: automatic-production-trigger, cancel-in-progress: false`.
- In theory, `cancel-in-progress: false` means new runs queue behind the in-progress run. In practice, GitHub Actions cancels queued runs when too many pile up, or when the workflow_run / repository_dispatch events arrive faster than the runs complete.
- Evidence: 5 consecutive runs (2026-11-16 8:51–9:04 PM EST) — 1 succeeded (17 min), 4 cancelled with **zero jobs executed** (`gh run view` shows `JOBS` empty). The cancelled runs include both automatic triggers and manual `workflow_dispatch`.
- The successful run at 8:51 PM completed in ~17 minutes (within the new 30-min timeout), showing the timeout fix works when the run actually executes.

**Secondary factor — selector speed:**
- The selector takes ~8 minutes because it fetches every merged migration PR via GitHub API and checks their status. With 986 production ledger versions and hundreds of PRs, this is slow but not the primary blocker.

**Why this is not a CI problem:**
- All required CI checks (`SQL migration guards`, `supabase/tests against an ephemeral database`, `Destructive SQL outside migrations`) pass on every PR. The problem is exclusively in the production promotion pipeline.

**The #6352 stale-PR issue is already fixed:**
- Commit `c658a0730` ("Skip promotion candidates already in the production ledger") is on main. The selector correctly skips PRs whose versions are in the production ledger.

### 7. Approaches considered and REJECTED

| Approach | Why rejected |
|---|---|
| **Increase timeout only (PR #6489)** | Necessary but not sufficient. The runs get cancelled before jobs execute — timeout doesn't help if the job never starts. |
| **`cancel-in-progress: true`** | Would cancel the in-progress promotion run mid-apply, potentially leaving a migration half-applied. Dangerous for a production pipeline. |
| **Remove the concurrency group entirely** | Would allow parallel selector runs, which could dispatch two promotions simultaneously. The serial lane is a safety feature (one migration at a time to production). |
| **Reduce trigger frequency (e.g., remove `workflow_run` listener)** | The `workflow_run` listener is what chains promotions (run completes → nudge → next run). Removing it would leave the queue idle until the hourly cron. |
| **Make the selector faster (cache PR scan)** | Real improvement but not the root cause. The selector completes in ~8 min when it runs; the problem is that runs don't start. |
| **Batch independent migrations in parallel** | Future improvement. Requires dependency analysis and is a safety trade-off. Not needed to clear this jam. |

### 8. Design decisions already made

**LOCKED — do not relitigate:**
- The serial lane (one migration at a time to production) is a safety feature and stays.
- `cancel-in-progress: true` is rejected (could kill a mid-apply production migration).
- The timeout stays at 30 minutes (PR #6489).
- The #6352 fix (skip already-applied versions) is already in place and stays.

**OPEN — implementer's judgment:**
- Whether the early-exit guard is a shell step in the workflow or a change to the selector's entry point. The guard must be **cheap** (no API calls) and must **exit 0** (skip, not fail).
- Whether to also deduplicate triggers (e.g., skip if the selector would return `wait` anyway) to prevent queue buildup. Criteria: the fix must not require API calls to decide.

---

## Part 3 — How to build it

### 9. The plan

**Phase 1: Fix the concurrency cancellation (one session)**

**Step 1: Add an early-exit guard to `automatic-production-trigger.yml`**

- **Target:** `.github/workflows/automatic-production-trigger.yml`
- **What to change:** Add a step at the **top** of the `trigger` job (before the checkout) that checks whether a `Shared Supabase Migrations` workflow run is currently in progress. If one is, echo a skip message and exit 0 immediately. This is the cheap guard that prevents runs from piling up in the concurrency queue.

  Implementation: use `gh run list --workflow "shared-supabase-migrations.yml" --status in_progress --limit 1` (or the GitHub API via `gh api`) to check for in-progress runs. If any exist, `echo "skip: a migration workflow run is in progress"` and `exit 0`.

  **Important:** This guard must use `GITHUB_TOKEN` (already available) and must NOT use `SUPABASE_ACCESS_TOKEN` (no DB access needed). It must complete in under 5 seconds. If the `gh` command fails (API error), treat as "no in-progress run" and continue (fail-open for the guard — the selector has its own `wait` logic).

- **How it should behave:** When a migration workflow is running, the trigger job exits immediately with success (skip). No queue buildup. When the lane is free, the guard passes and the selector runs normally.

- **Dependencies:** None. This is the first change.

- **Verification gate:** Trigger the workflow manually while a migration workflow run is in progress. The trigger job should complete in under 30 seconds with the skip message. Trigger again when the lane is free — the selector should run.

**Step 2: Ensure the selector's `wait` return also exits cleanly**

- **Target:** `scripts/automatic_promotion_candidates.py` (line 426–427)
- **What to change:** Verify that when the selector returns `wait`, the calling workflow treats it as a clean exit (exit 0), not a failure. Check the workflow's step for `automatic_promotion_candidates.py` — it should not `continue-on-error` or mask a non-zero exit, but the selector's `wait` return should map to exit 0.

  If the selector currently exits non-zero on `wait`, change it to exit 0 (the `wait` is expected behavior, not an error).

- **Verification gate:** `python scripts/automatic_promotion_candidates.py --dry-run` with a mock in-progress run returns exit code 0 and prints the `wait` message.

**Phase 2: Verify the queue drains (can follow immediately)**

**Step 3: Trigger a promotion and verify it dispatches**

- **What to do:** After Steps 1–2 merge to main, trigger the promotion workflow manually. Verify that:
  1. The run completes (not cancelled)
  2. The selector dispatches the next eligible migration PR (should be one of #6263, #6260, #6316, #6436 — or the designflow-backend#408 migrations if those are further along)
  3. The dispatched migration workflow runs and either applies or fails cleanly

- **Verification gate:** The trigger run shows `dispatch: PR #<N> versions <V> not yet in production` in its log. The dispatched migration workflow appears in the Actions tab.

**Step 4: Verify designflow-backend#408 migrations reach production**

- **What to do:** Once the queue drains past the exhausted PRs, verify that migrations `20261115132055` and `20261116120000` are applied to production.

  Command (read-only):
  ```sql
  select version from supabase_migrations.schema_migrations 
  where version in ('20261115132055','20261116120000');
  ```
  And:
  ```sql
  select to_regclass('plm.dcp_property_mg06_crosswalk'), 
         to_regprocedure('plm.suggested_property_for_sku(text)');
  ```

  Connect via: `psql "host=aws-1-us-east-1.pooler.supabase.com port=6543 dbname=postgres user=postgres.qsllyeztdwjgirsysgai sslmode=require"` with password from 1Password `vibe_coding` → `Supabase DB Password - shared POP database`.

- **Verification gate:** Both versions appear in `schema_migrations`. The table and function exist.

**Phase 3: Live proof (Step 5 of designflow-backend#408)**

**Step 5: Capture sandbox screenshots and update issue #408**

- **What to do:**
  1. Open `https://alsand.designflow.app` and navigate to an Item Detail page for a SKU with Disney art (e.g., `3FZ27DYLS01` — Stitch art, or `3FZ27DYNX01` — Nightmare Before Christmas).
  2. Verify the "Suggested from art: X (n files)" hint appears near the Property select.
  3. Verify the amber "Art suggests X" warning appears when the saved property differs from the top suggestion (use the Aristocats SKU `MQZ93DYCP01` currently on Classic Characters).
  4. Take screenshots of both states.
  5. Update the STATUS table on `https://github.com/popcre/designflow-backend/issues/408` — check off steps 1–5 with evidence.

- **Verification gate:** Screenshots attached to issue #408 comment. STATUS table shows all steps ✅.

### 10. Tests required

- **No new unit tests needed** for the workflow change (Step 1) — it's a CI configuration guard, not application code.
- **Existing tests that must stay green:** `python -m unittest discover -s scripts -p 'test_automatic_promotion_candidates.py' -v` (the selector's test suite). The selector logic is unchanged in this plan.
- **Manual verification:** the `gh run list` check for in-progress runs is the test. Run it twice (with and without an in-progress migration) to confirm the guard works.

### 11. Constraints, standing rules, and gotchas

- **The serial lane is a safety feature.** Never allow two production migration applies simultaneously.
- **`cancel-in-progress: true` is dangerous** — it could kill a production apply mid-transaction.
- **The guard must be cheap** (no Supabase access, no heavy API calls) and must **exit 0** on skip. A non-zero exit would fail the workflow and create noise.
- **`shared-db` uses branches and PRs.** The merge queue controls the merge strategy.
- **Commit author:** `Albert Hazan <u2giants@users.noreply.github.com>`.
- **Sign commits** with `Posted by MiMo chat <id> on <machine>`.
- **The repo is PUBLIC.** No personal identifiers in anything written.
- **Never edit a migration that has already been applied.** The fix is in workflow configuration, not in migration files.
- **The selector's `wait` return is expected behavior** — it should not be treated as an error.

### 12. Access and environment

- **Repo:** `popcre/shared-db` — GitHub, `gh` CLI authenticated
- **Working copy:** `D:\repos\shared-db` (shared checkout — use a worktree per `docs/agents/worktrees-and-handoffs.md`)
- **Production DB:** 1Password `vibe_coding` → `Supabase DB Password - shared POP database`. Pooler `aws-1-us-east-1.pooler.supabase.com:6543`, user `postgres.qsllyeztdwjgirsysgai`.
- **Sandbox:** `https://alsand.designflow.app` (DesignFlow sandbox for live proof)
- **CI:** GitHub Actions. Required checks: `SQL migration guards`, `supabase/tests against an ephemeral database`, `Destructive SQL outside migrations`

---

## Part 4 — Landing it

### 13. Definition of done, risks, open questions

**Done when (each item cites an artifact):**
- [ ] Early-exit guard exists in `automatic-production-trigger.yml` — evidence: file diff showing the guard step
- [ ] Selector `wait` exits 0 — evidence: `python scripts/automatic_promotion_candidates.py --dry-run` with mock in-progress run, exit code 0
- [ ] Promotion run completes and dispatches — evidence: trigger run ID showing `dispatch: PR #<N>` in log
- [ ] designflow-backend#408 migrations on production — evidence: `select version from supabase_migrations.schema_migrations where version in ('20261115132055','20261116120000')` returns 2 rows
- [ ] Sandbox screenshots captured — evidence: attached to issue #408
- [ ] Issue #408 STATUS table updated — evidence: all 5 steps checked ✅

**Risks:**
- The guard might skip too aggressively (e.g., if a stale in-progress run blocks new dispatches). Mitigation: the guard only checks `in_progress` status, and runs timeout after 30 minutes. A stale run would time out and free the lane.
- If the exhausted PRs (#6263, #6260, #6316, #6436) keep getting retried despite being "out of attempts," they could still block the queue. The selector's exhausted-PR pass-over logic handles this (verified in code, line 538–547).

**Open questions:**
- Whether to also add a `concurrency` `cancel-in-progress: false` **queue limit** (GitHub doesn't support this natively). The early-exit guard is the workaround.
- Whether the 4 exhausted PRs on #6352 need individual repair before the queue fully drains. The selector passes over them, so newer PRs should promote regardless. But if the exhausted PRs' migrations have ordering dependencies with newer ones, there could be issues. Implementer should verify by checking if any pending migration has a `derived-from` or dependency on an exhausted PR's version.

---

## Self-audit

1. **Could a brand-new AI session execute this plan without asking anything?** Yes. Section 5 names every file with its current state. Section 9 Step 1 gives the exact guard implementation (check `in_progress` runs, exit 0 on skip, fail-open). Section 12 gives the repo and DB access. Verification gates are runnable commands.

2. **Does the plan carry every piece of background and reasoning?** Yes. Section 3 has the full incident timeline. Section 6 has the root-cause analysis with evidence (5 cancelled runs, zero jobs). Section 7 documents 6 rejected approaches. Section 8 labels locked vs. open decisions. Section 11 names the serial-lane safety constraint explicitly.

3. **Is the ultimate goal clear enough for judgment calls?** Yes. Section 1 states "migrations reach production within 30 minutes of merge" with the specific unblock target (issue #408 migrations). If the guard approach doesn't work, the implementer can evaluate alternatives against "does this get the migration to production safely?"
