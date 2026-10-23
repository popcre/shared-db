# Critique of plan_ci-speedup.md — 2026-10-23

Author: ZCode chat (session id unavailable) on `edge-dev`, 12:40 PM EDT. Task class: private-evidence (read-only). Base checked: b2d1fa3bd127.

## Verdict

Direction is right, the evidence is real, and Phase A alone removes the worst recurring stall — worth executing. But the plan is **not executable as written**: two steps conflict with standing owner rulings or refused policy (B2, C2), one has an unbuilt core mechanism (B1's SHA binding), and one is an investigation wearing a step's clothes (D1). Several file pointers are wrong. Fixes below; recommended sequencing at the end.

Note: PR #4682 has since merged and branch activity continued past the handoff (runs at 2026-10-23T16:16Z), so the RLS context work is done; only this speedup plan remains open.

## Claims that verified (with corrections)

- **A1's constant is real but the plan names the wrong file.** `AUTHOR_CHECKIN_INTERVAL_MINUTES = 10` lives in `scripts/lib/lanes/constants.mjs:58` — `manage-migration-author-lanes.mjs` only imports/re-exports it (line 55). A fresh session editing "manage-migration-author-lanes.mjs" per the plan finds no constant to change.
- **The 10-minute message is a hardcoded string** — `scripts/manage-migration-author-lanes.mjs:4358` throws `'author check-in confirmation is missing, future or older than ten minutes'`. Widening to 60 makes that message a lie; it must be derived from the constant, and `nextCheckinMinutes` (line 4380) already does this correctly.
- **B1's refusal string is real but lives elsewhere**: `scripts/lib/review-packet.mjs:34` (`production-risk request applies only to a merged source pull request`), not in `run-governed-review.mjs`. Same fix-by-rg applies, but the self-audit's "exact files and functions" claim is weaker than stated.
- All named scripts and test files exist (checked: `prove-production-risk-acceptance.mjs` + test, `check-migration-pr-lease.mjs` + test, `run-governed-review.mjs`, `agent-work-contract*`).
- **Workflow triggers are already correct**: all four workflows have plain `pull_request` triggers with no `paths:` filters (`pr-guards.yml:36` carries the "NO `paths:` FILTER, ON PURPOSE" comment). On PR #4682's later heads everything ran normally (run list at 2026-10-23T16:16:29Z shows PR Guards, Migration Author Lease, Shared Supabase Migrations, Merge Queue Gate, Database Contract Tests). See D1 below — this cuts against the plan's assumed fix.

## Blocking problems

### 1. Step B2 contradicts owner ruling §6.23 — cut it

Ruling 2026-09-30: production risk classes are accepted by the allocator-assigned AI reviewer's durable exact-head assessment, **never by Albert**. An `owner-authorized-skip` record in the evidence JSON is Albert accepting production risk by instruction — precisely what the ruling forbids. The observation-week rule independently keeps shared-db and production waiting for an exact-head APPROVE even when `MERGE-UNREVIEWED` lets other repos merge; and the sole standing production exception in the global rules is the activated automatic promotion workflow — a plan file cannot mint a new exception class. (The "database writes skip that APPROVE" clause in the global rules is the one argument the other way; if Albert wants that reading, it must be settled as a dated owner ruling in `docs/owner-rulings.md` through the rulebook-change path first.)

Albert's actual 2026-10-23 instruction — "don't do a second review for #4430" — is fully satisfied by Step B1. If no reviewer is available at all, that is a platform limit: report `Blocked —`, don't build a through-lane. Delete B2 from the STATUS table and Definition of Done; B2's own open question ("does the owner want this permanently?") concedes the authorization doesn't exist yet.

### 2. Step B1 has an unbuilt binding — a pre-merge block cannot name the production target

The lane merges with a merge commit: `gh pr merge --merge --match-head-commit` (`guarded-migration-merge.yml:486`), so the promoted main SHA ≠ the PR head SHA. That is exactly why `scripts/lib/review-packet.mjs:34` requires `pullRequest.merged === true`, and `scripts/prove-production-risk-acceptance.mjs:54` rejects any block whose `main_sha` is not "the exact promoted main" (40-hex, compared at apply time). B1 proposes recording the block at the PR head — **the SHA its own adversarial table requires does not exist yet at that moment**.

B1 must define the binding before implementation. The workable shape: the block binds the PR head SHA; at apply time the proof re-derives the merge commit and accepts only if the merge commit's tree equals the reviewed tree (the `pr-content-equivalence.mjs` normalization discipline), with the apply pin (2026-08-11 incident) still refusing when main moved. The verification gate must also name the freeze interaction (standing fact 14): a pre-merge assessment widens the review→apply window, and the pin + promotion freeze are the compensating controls.

### 3. Step C2 re-opens the exact equivalence widening §5.0-C refuses

AGENTS.md §5.0-C (2026-09-20): widening review equivalence beyond `.agent/` files is REFUSED — "widening equivalence… would be reviewing less, not reviewing faster." C2 widens it to migration filename/version renames, and the version is material: it determines apply order and ledger position (the 2026-07-31 four-way collision keys on versions). If C2 survives at all, it needs all of:

1. Content comparison with strict version-string-only normalization, plus hostile-input tests in the B1 table style — a loose normalizer could hide SQL body edits inside a "rename."
2. Duplicate/backdated-version collision checks re-run on the **new** version before the old APPROVE is reused.
3. Landing as an explicit rulebook change (§5.0-C wording in AGENTS.md + `docs/agents/merge-protocol.md`) with a different-engine reviewer's APPROVE on the widening itself — not as a quiet edit to `pr-content-equivalence.mjs`.

Defer C2 behind that decision. It is the lowest-value, highest-risk step in the plan.

### 4. Step D1 is an investigation whose assumed fix has nothing to fix

The trigger config is verified correct (no paths filters; PR #4682's later heads ran everything). So "remove that skip" targets a skip that doesn't exist. The observed first-head failure was an event-level anomaly — leading hypotheses: GitHub event-delivery loss at PR open, or the branch's first head pushed by something whose events don't trigger `pull_request` workflows (check who/what pushed the first head of `mimo/rls-4430-live`; a GITHUB_TOKEN-pushed head doesn't fire `push`/`pull_request` for later syncs — though the PR author shows as `u2giants`, the first-head pusher is the open question).

Re-scope D1's deliverable: detection and recovery, not config — e.g., a watchdog (scheduled or `workflow_run`) that finds open PRs missing required check runs and dispatches them. A config-only change cannot guarantee the 2-minute gate against transient event loss.

## Design corrections (non-blocking)

- **A2 fights the lane's own security design.** The Prepare job deliberately mints a **read-only** API token (`guarded-migration-merge.yml:188`); triggering `gh run rerun` requires `actions: write`. The lane also has an existing "Require main and rerun coordination guard" step (line 366) whose assumptions an in-lane auto-rerun may violate. Prefer the plan's own one-line alternative as the primary: re-trigger at the source — the `--check-in-author` path fires a `repository_dispatch` that re-runs `migration-author-lease.yml` for that PR; one retry, then refuse. Note branch protection still requires the check green, so "Prepare revalidates and ignores the stale red run" is not an option; the rerun must genuinely happen somewhere with write authority.
- **A1's window should be lease-remaining, not a flat 60.** The open question already concedes this — make it the design (`min(cap, minutes-until-lease-expiry)`, cap in `constants.mjs`).
- **A1 and B1 both need rulebook edits the plan doesn't list.** "Ten minutes" is stated in durable rulebook files — `docs/agents/anti-collision-summary.md`, `docs/agents/section-4-anti-collision-rules.md`, `docs/agents/owner-rulings.md`, `docs/owner-rulings.md`, `docs/advisory-lock-registry.md` — which must change in the same PR (operating rules and their chapters move together; verification evidence under `docs/verification/` is history and stays). B1/B2 behavior is described in `docs/production-promotion-procedure.md` and `docs/agents/current-workflow.md`; B1 must update them.
- **No landing strategy.** Recommend: PR 1 = A1 alone (smallest diff, kills the biggest recurring pain); PR 2 = A2; PR 3 = B1 with the binding designed; D1 investigation in parallel; C1 anytime; C2 deferred pending the equivalence decision; B2 deleted. Each PR gets the standard different-engine review; nothing here is documents-only.
- **Definition of done lacks the goal metric.** "Minutes, not an hour" is unmeasurable as written. Add a gate: the next real structural change goes green-CI → applied with live proof in ≤ 20 minutes, timing recorded in the STATUS table.
- **STATUS numbering mismatch:** the table lists Steps 1–7; the body uses A1…D2. "Fresh session starts at Step 1" forces a guessing game.
- **Self-audit overstates readiness.** §13's open questions include choices a fresh session cannot make (window value, rebind policy, unreviewed-week permanence) and D1 has no root cause; "execute without asking anything" is false until those close.

## Minor

- §11 hardcodes `Posted by MiMo chat` — each successor session signs with its own identity.
- The plan and its handoff are untracked at repo root; the repo's wrap-up convention says don't leave untracked docs behind — land them with PR 1.
- I did not re-verify the cited CI run/job logs (39970394727, 39972517357, 39975696968, 120464882429/120469254384); those are accepted from the authoring session's record. Every repo-state claim above was checked directly at the cited locations.

---

## Addendum — 2026-10-23 after the owner's ruling (~1:00 PM EDT)

**Owner ruling, verbatim, from Albert's chat to ZCode this session:** "yes, skip should exist because reviewer tooling keep failing over and over again and prevent us from doing anything."

This **supersedes Blocking problem 1**. B2 stays — redesigned, not as the plan had it:

### B2 redesigned — automatic reviewer-outage skip

- **Trigger is mechanical, never a human decision:** a governed-review dispatch that failed, was skipped, or found the pool quarantined/empty — recorded with engine, timestamp and error (the `ai-reviewer-issue` record already captures this). No label anyone must remember, no per-PR judgment.
- **Controls kept — none re-adds the removed wait:** green CI on the exact head; the guarded merge lane (lease, head re-proof, freeze check); version/collision checks; the apply pin refusing moved main; mandatory post-apply live proof against production; the outage evidence stored in the evidence JSON as `reviewer-outage-skip`; an advisory retro-review whenever a reviewer next recovers — never blocking.
- **B1 remains the default path**, so the outage skip is the rare fallback, not the route.
- **Landing requirements:** the PR adds the ruling to `docs/owner-rulings.md` framed as *the owner accepting the business risk of proceeding during reviewer-tooling outage* — not as Albert performing technical review, so §6.23 stands unchanged — and updates the observation-week sentence in AGENTS.md ("shared-db… still wait for an exact-head APPROVE") in the same PR.

### Additional cuts (verified today; beyond the plan's Phases A–D)

1. **Bound the 50-minute aggregate patience; auto-replace lane jobs that never start.** `pr-guards.yml:784` runs `runner-lanes.mjs --aggregate --timeout-minutes 50`; on 2026-10-23 the #4682 head's PR Guards run was still in progress at 30m51s. The lane-replacement machinery already exists (dispatch with a `lane` input). Add a watchdog: a registered lane run absent after ~5 minutes → auto-dispatch the replacement; the aggregate refuses only if the replacement also fails. This also fixes the plan's D1 failure class (required CI that never started) without touching trigger config.
2. **Stop paying up-to-15-minute API-quota sleeps.** The collision steps set `GITHUB_RATE_LIMIT_MAX_WAIT_SECONDS: '900'` (pr-guards.yml ~706–751). Widen the pop-ai-watchers app-token budget/lane so quota exhaustion no longer stalls merges. Identical checks, separate budget.
3. **Speed — do not skip — the ~12-minute ephemeral-database check.** Cache the provisioned baseline. Path-filtering required checks is forbidden by the §5.2 stale-verdict doctrine; do not "optimize" it back in.

### Already cut — do not re-propose (verified current state today)

- Preview and production apply queues are separate since #3781 Step 10 (`shared-supabase-migrations.yml:124-137`).
- The merge lock no longer covers preflight or quota waits since #3779 Step 9 (`guarded-migration-merge.yml:25-36`).
- Strict up-to-date branch checking is off by owner ruling 2026-08-19 (issue #1286, ~50 min/day).
- Stale-place nudge for the protected-source queue is implemented with a 1-hour window (`scripts/check-pr-source-collisions.mjs:91-106`).
- Documents-only PRs already have a fast admin-squash lane.

### Deliberately NOT added back

No second reviewer anywhere; no new human approval or label to remember; no polling loop a session must babysit (the watchdog is a scheduled workflow); no review-equivalence widening beyond B1's tree binding (plan Step C2 stays deferred pending its own ruling); no path filters on required checks.

### Sequencing (updated)

PR 1 = plan A1 · PR 2 = B1 + B2 redesign + owner-rulings entry · PR 3 = cuts 1–2 · plan C1 anytime · plan C2 deferred · plan D1 folds into cut 1.
