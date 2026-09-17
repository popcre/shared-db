---
issue: 3199                            # the issue that proves this done
status: OPEN                           # OPEN or BLOCKED — never DONE, see below
owner: zcode/plan-orchestrator-required-load-reduction
---

# Orchestrator required-load reduction — plan written, execution not started

**What this is.** Tracking the program to reduce what MUST pass through the
shared-db orchestrator session without reducing safety: queue hygiene
(labels, expired-claim close-out, read-only report workflow), a self-service
additive lane for app-owned schemas (`crm`/`pim`/`dam` + brand-new schemas
only), and a zero-touch audit of the #2758 ephemeral route's merge→production
hops. The controlling document is
[`plan_orchestrator_required_load_reduction.md`](../plan_orchestrator_required_load_reduction.md) —
**read its STATUS table first.** Issue: [#3199](https://github.com/u2giants/shared-db/issues/3199).

**Where it stands.** Plan authored 2026-09-17 (this session, task class
`prose`, worktree `C:\repos\shared-db\.claude\worktrees\orchestrator-load-plan`,
branch `zcode/plan-orchestrator-required-load-reduction`). **The Muse Spark
1.3 opinion the owner asked for has NOT been obtained:** `ai-muse` failed
twice on 2026-09-17 with "Muse returned malformed event output" (sessions
`orchestrator-load-plan-review` and `-2`, both left fenced per protocol;
incomplete evidence under `.ai/reviews/`). Retrying the review is the first
open item before this plan's phases start. No phase has been executed.

**Next exact action.** A fresh session starts at plan Step A1: `git fetch
origin --prune`, re-run `node scripts/manage-migration-author-lanes.mjs
--queue-audit` for today's unlabelled list (the plan's 2026-09-17 list will
have moved), then label each issue scope-block-first. Declare the task class
before working (`ai-task-gates start --class …`).

**Do not:** re-plan #2530 here, parallelize the serial lanes, add an
auto-label bot, loosen the Phase B boundary into shared schemas, or weaken
any caller check in the guarded merge workflow (Step B3's safe default is
"change nothing"; #2530's queue owns that hop).
