# Implementation plan — reduce what MUST pass through the orchestrator, without reducing safety

Tracking issue: [#3199](https://github.com/u2giants/shared-db/issues/3199) (`db-work` label; `db-work-scope` block with `work_type: repo-maintenance`, `route: repo-maintenance`).

Companion plan (do NOT re-plan it here): [`plan_shared_db_popcre_transfer_merge_queue.md`](plan_shared_db_popcre_transfer_merge_queue.md) — issue #2530, the org transfer + native merge queue.

Paired handoff: [`HANDOFF.d/2026-09-17T1325Z-zcode-plan-orchestrator-load-reduction.md`](HANDOFF.d/2026-09-17T1325Z-zcode-plan-orchestrator-load-reduction.md)

## STATUS — read first

| Step | State | Date | Evidence / next gate |
|---|---|---|---|
| A1. Label every open unlabelled issue (scope block verified first) | ⬜ open | 2026-09-17 | Rerun `node scripts/manage-migration-author-lanes.mjs --queue-audit`; the `UNLABELLED ISSUES` block must be empty. |
| A2. Close out expired author-lease claim #3089 (PR already merged) | ⬜ open | 2026-09-17 | Same audit; the `EXPIRED AUTHOR LEASES` block must no longer list claim #3089. |
| A3. Ship read-only `Queue Hygiene Report` scheduled workflow | ⬜ open | 2026-09-17 | One green `workflow_dispatch` run whose permissions block proves it cannot write. |
| B1. Ship the self-service additive-lane boundary classifier + tests | ⬜ open | 2026-09-17 | `node --test scripts/check-self-service-additive-lane.test.mjs` green, dirty fixtures first; wired into a CI workflow. |
| B2. Admit `self-service-additive` route for author claims, excluded from orchestrator pickup | ⬜ open | 2026-09-17 | `--queue-audit` prints a separate self-service section; `NON_STRUCTURAL_EXITS` and the AGENTS.md §0.0-C table changed in the SAME pull request; sync test green. |
| B3. CI guard workflow for self-service pull requests + decide the merge-caller question | ⬜ open | 2026-09-17 | Guard refuses a deliberately out-of-boundary fixture PR in a dry run; merge-caller decision written down with its reasoning. |
| B4. Document the lane (AGENTS.md, both `shared-db-change` skills, memory) | ⬜ open | 2026-09-17 | A fresh cold session can execute the lane from the documentation alone. |
| C1. Write the merge→production hop table for the #2758 ephemeral route | ⬜ open | 2026-09-17 | Hop table merged as docs; every hop names actor and why manual. |
| C2. Automate only pure-mechanics hops; guard-judgment hops stay manual and documented | ⬜ open | 2026-09-17 | Each automation has tests in the style of `scripts/test_production_preview_skip.py`; no refusal semantics removed. |
| D. Landing: STATUS upkeep per phase; retire handoff when the tracking issue closes | ⬜ open | 2026-09-17 | Plan STATUS current at every merge; handoff deleted in the closing change. |

**Fresh implementation starts at Step A1.** Natural context cut points: after A3, after B4, after C1. Before each phase, re-read this STATUS table, `git fetch origin` and re-derive the live queue state — the counts in §3 are the 2026-09-17 reading, not standing truth.

---

## 1. Ultimate goal

Today every structural database change in this company funnels through ONE orchestrator session, and that session is chronically backed up, so applications wait on it for work whose safety does not actually depend on it. When this plan is done:

- An application session that needs a **small additive change confined to its own app-owned schema** (a new extension table, a new column on its own ext table, a new view in its own schema) can take that change from idea to merged pull request **without ever waiting for orchestrator attention**, while passing through every existing safety gate unchanged.
- The queue stops losing work to **administrative silence** (unlabelled issues, expired leases nobody closed) because a read-only report surfaces them daily.
- The remaining manual hops between merge and production for already-classified low-risk changes are either automated (if they are pure mechanics) or written down with the reason they must stay manual.
- The orchestrator session's context is reserved for what genuinely needs judgment: shared-object structural changes, contention, and owner decisions.

**The safety floor is NOT negotiable and NOT reduced.** The serial one-at-a-time preview apply, guarded merge and production promotion lanes; exact-head review verdicts; exact-object collision locks and version reservation; the two-reviewer rule for migrations; the curated Master Data gate (§6.4); and the full orchestrator path for anything touching a shared object — all unchanged. If any step in this plan conflicts with that floor, **the floor wins — stop and flag it** rather than implementing the step as written.

## 2. What this application is

`shared-db` (`u2giants/shared-db`, public; transfer to `popcre` planned under #2530) is the canonical repository for the schema, migrations, policies and coordination machinery of ONE Supabase/Postgres database shared by CRM (`popcrm-web`), DAM (`popdam-web`), PM/PIM (`poppim-web`) and six `popcre/designflow-*` PLM repositories. Pushes to `main` mirror the repo root into nine consumer repositories.

Its distinguishing mechanism: a single **orchestrator session** (found via `node scripts/check-orchestrator-marker.mjs --resolve`) triages `db-work`-labelled GitHub issues, admits structural work, dispatches it to sub-agents in isolated worktrees, draws reviewers, and drives guarded merges and production promotion. Nearly all safety is enforced by **scripts and GitHub-backed locks**, not by the orchestrator's judgment: `scripts/manage-migration-author-lanes.mjs` (claims, object locks, version reservation, queue audit, reviewer draw), `.github/workflows/guarded-migration-merge.yml` (exact-head approval gate), `scripts/dispatch-production-apply.mjs` + `scripts/production_business_risk_gate.py` (production lane and the #2758 low-risk "ephemeral" classifier `preview_required_reasons`), and the CI guards run on every pull request.

This plan is repository-maintenance work: it changes scripts, workflows and documents in this repository. It authorizes **no database schema or row change** and touches no credentials.

## 3. What triggered this work

Albert's observation on 2026-09-17: *"the orchestrator is always backed up and holds everything else back as well."* A read-only queue audit and PR listing run that day agreed, and located the backlog:

- **Merge-stage aging.** `gh pr list --repo u2giants/shared-db` showed open pull requests dating to 2026-09-08 (#2607) and 2026-09-12 (#2835, #2846) — waiting on merge attention, not on safety checks.
- **Administrative pile.** `node scripts/manage-migration-author-lanes.mjs --queue-audit` (2026-09-17 run; re-derive rather than trusting these numbers, per the §4.3 owner ruling) printed: ten `UNLABELLED ISSUES` — **including #2530 itself**, so the queue's highest-leverage relief plan was invisible to label-filtered queries; an `EXPIRED AUTHOR LEASES` entry for claim #3089 whose pull request was already merged (bookkeeping debt; expiry never releases object protection, so the claim still holds its objects); and a large `NOT ORCHESTRATOR WORK` block of repo-maintenance issues that are legitimately outside the orchestrator but inflate everyone's sense of the queue.
- **Authoring itself was healthy.** Four author lanes with active, fresh leases. The bottleneck is attention and serialization, not capacity.

The deepest relief — GitHub's native merge queue — already has a full plan (#2530), but its STATUS shows Steps 1–2 done and everything after gated on **Step 0: the owner's explicit transfer authorization and change window**, then the org transfer, then queue rebuild (Steps 7–8). That relief is real but not imminent. This plan delivers relief that does NOT wait on the transfer.

## 4. Scope

### In this plan

- **Phase A — queue hygiene:** label currently-unlabelled open issues (verifying each scope block first); close out expired claim #3089 through the guarded release path; add a scheduled read-only `Queue Hygiene Report` workflow that surfaces unlabelled issues, expired leases and aging non-orchestrator work daily without writing anything.
- **Phase B — self-service additive lane:** a mechanically-classified route (`self-service-additive`) letting an application session claim an author lane, author, review and land additive changes **confined to app-owned schemas** without orchestrator triage/dispatch, keeping every existing gate.
- **Phase C — zero-touch wait chain:** a written audit of every manual orchestrator turn between merge and production apply on the #2758 ephemeral (low-risk) route; automation of pure-mechanics hops only.
- **Phase D — documentation landing:** AGENTS.md, both `shared-db-change` skills, memory entries, plan STATUS upkeep.

### NOT in this plan

- **No second orchestrator session.** The marker system assumes exactly one; changing that is a separate, later decision (see §7).
- **No re-planning or execution of #2530** (org transfer, merge queue). This plan depends on it only for the merge-serialization end-state.
- **No parallelizing the preview, merge or production lanes.** Owner ruling 2026-09-11: those one-at-a-time lanes are safety isolation. Never reintroduce a count limit or a parallel apply.
- **No weakening of any gate:** required checks, exact-head approvals, two reviewers for migrations, object collision locks, version reservation, admission tests, business-risk conclusions.
- **No auto-labeling bot.** The `db-work` label drives admission; a bot applying it can silently misroute work (see §7).
- **No change to the curated Master Data gate (§6.4)** or its matched-row abstention rule.
- **No database schema or data changes, no credential or secret work, no consumer-repo changes** (skill-file copies under user directories are documentation, not consumer-repo sync targets).
- **No extension of the self-service boundary to shared schemas** (`plm`, `api`, `core`, `public`, anything cross-app) — not now, not as a "quick addition" later without a new owner decision.

## 5. Current state of the code

Baseline read from `origin/main` on 2026-09-17 (worktree cut at `ae7145128de8`). Orientation only — re-derive before executing.

### The pieces this plan builds on (all existing, all working)

- `scripts/manage-migration-author-lanes.mjs` (~8,600 lines): `--claim --admit-issue <n>` (lane + objects + version reservation, GitHub-backed, fail-closed), `--queue-audit` (reads every open issue; prints `NOT ORCHESTRATOR WORK`, `UNLABELLED ISSUES`, `EXPIRED AUTHOR LEASES`; exits 2 while unlabelled issues exist), `--assign-reviewer` (automated draw from the rotation minus the live orchestrator's engine), `--release-claim <n>` / `--recover-expired-claim-from-pr` / `--renew-claim` (guarded claim close-out; owner checks, no-open-PR check, mutex), and the machine-readable admission/route table `NON_STRUCTURAL_EXITS`, which §0.0-C of AGENTS.md mirrors in prose and which must stay in sync with it.
- `.github/workflows/guarded-migration-merge.yml` + `scripts/check-exact-head-approval.mjs`: the merge gate; runs twice (up front, then re-proven under the merge lock).
- `scripts/dispatch-production-apply.mjs` + `scripts/production_business_risk_gate.py`: the production lane and the #2758 carve-out — `ephemeral_check_run_id` (the job id of the `supabase/tests against an ephemeral database` check) substitutes for preview proof when the conservative classifier (`preview_required_reasons`) recognizes the migration as low-risk; anything unrecognized (rewrites, long locks, drops, backfills, unknown statements) still requires preview. Tests: `scripts/test_production_preview_skip.py`, `scripts/test_automatic_qualification_route.py` (a successful rehearsal automatically qualifies and dispatches the serial production lane).
- `.github/workflows/documents-only-merge-authorization.yml` + `scripts/check-documents-only-merge-authorization.mjs` + `scripts/lib/documents-only-change.mjs`: the rule-18 documents-only PR path (no reviewer required).
- `.github/workflows/tools-offline-tests.yml`: the pattern to copy for new guards — **own workflow, NO `paths:` filter** (a repo-wide scanner behind a narrow trigger reports stale greens), offline-only tests, and explicit wiring of every new test (the PR #331 lesson: a test referenced by no workflow guards nothing).
- `.github/workflows/domain-ownership.yml`: the minimal required-context workflow shape.
- `plan_shared_db_popcre_transfer_merge_queue.md` (#2530): 12-step evidence-gated plan; STATUS shows Steps 1–2 done on 2026-09-17, Step 0 (owner authorization + window) open and blocking Steps 3+, merge queue at Steps 7–8.

### What does NOT exist yet

- No `self-service-additive` route anywhere (admission table, audit output, docs).
- No boundary classifier for app-owned-schema additive changes.
- No scheduled queue-hygiene report (the queue audit exists but only runs when a session runs it).
- No written hop table for the ephemeral route's merge→production path.

## 6. Key findings and root cause

1. **Safety no longer lives in the orchestrator session's attention.** It lives in the GitHub-backed locks, CI guards, exact-head review gate, reviewer rotation and serial lanes — all of which execute without the orchestrator's judgment. The owner's 2026-09-16 no-ceilings ruling made this explicit: the only admission controls that matter are exact-object collision locks, version reservation, and the serial apply/merge/promote lanes. The orchestrator session is therefore mostly a **scheduler and clerk**, and scheduler/clerk work is exactly what can be removed without touching the safety floor.
2. **The backlog is at the merge stage and in administration, not in authoring.** Lanes were fresh; PRs aged at merge; ten issues were invisible for want of a label; one merged PR's claim was never released. Each is an attention problem, not a capacity or correctness problem.
3. **The biggest single relief (native merge queue) is blocked behind the org transfer**, which is blocked on the owner's Step 0 authorization. Relief that does not depend on the transfer is therefore worth building now: remove orchestrator **traffic** (Phase B) and **administrative turns** (Phases A and C), and let #2530 remove the **serialization attention** later.
4. **The 2026-08-13 through 2026-09-16 trajectory already points this way.** §0.0-A freed reads, §0.0-B freed data writes, the 2026-08-21 ruling freed repo-maintenance, rule 18 (#2102) freed documents-only PRs from review, #2758 freed low-risk SQL from the preview apply, and the 2026-09-16 ruling removed every concurrency ceiling. Phase B is the next step on the same line: free the *least dangerous class of structural work* from orchestrator triage.

## 7. Approaches considered and REJECTED

- **A second orchestrator session.** The locks would still fail closed, but `scripts/check-orchestrator-marker.mjs` assumes a single live marker; two sessions racing triage, merge execution and marker writes need an arbitration redesign. Rejected **for now** — revisit only if Phases A–C plus #2530 leave real backlog. (This is the only rejected approach here that is rejected on sequencing, not principle.)
- **Parallelizing preview/merge/production.** Forbidden by the owner's 2026-09-11 ruling; those lanes are safety isolation. Not a backlog fix anyway — the waits are attention gaps, not lane occupancy.
- **An auto-labeling bot for unlabelled issues.** The `db-work` label is the admission trigger; a bot applying it from a guess would route work invisibly. The audit's refusal (exit 2) stays; the fix is a read-only report plus a human/session applying the label after reading the issue (Step A1's order: scope block verified BEFORE labelling).
- **Fewer reviewers for the self-service lane.** Migrations need two independent reviewers (§4 full text). The draw is automated, so reviews cost the orchestrator nothing — removing them would trade real safety for zero load reduction.
- **Skipping the author-lane claim for self-service work.** The claim's version reservation and object locks are the collision safety that lets unlimited authors coexist. Self-service keeps them; it only skips orchestrator triage/dispatch.
- **Batching several authors' migrations into one pull request** to reduce merge count. Blurs attribution, review targeting and rollback. The merge queue (#2530) is the correct serialization answer.
- **Letting the self-service classifier grow "just one" convenience case later** (an `alter table add column` on a shared table, a backfill, a grant change). Every one of those is how the boundary silently becomes the whole queue. Boundary changes require a new owner decision, and `plm`/`api`/`core`/`public` are permanently outside it absent that decision.
- **Changing the guarded-merge workflow's caller checks in this plan.** If self-service authors cannot dispatch the guarded merge themselves today, the interim answer is that the orchestrator (or any session the workflow already authorizes) still presses merge until #2530's queue replaces that hop. Do not weaken caller checks to save a hop (see Step B3).

## 8. Design decisions already made

**Locked (do not relitigate while executing):**

- **Safety floor** (§1 list): serial lanes, exact-head approvals, two reviewers for migrations, collision locks + version reservation, §6.4 gate, full orchestrator path for shared-object work. Locked by standing owner rulings 2026-09-11 and 2026-09-16, not by this plan.
- **Phase B boundary = additive-only, app-owned schemas only.** Initial set: `crm`, `pim`, `dam`, plus a brand-new schema any single app introduces (new-schema creation is itself additive). Explicitly OUT: `plm`, `api`, `core`, `public`, `ingest`, and any cross-app object. Rationale: §4.1 already routes app-specific attributes to per-app extension tables; a change confined to one app's schema can only break that app, which is the party best placed to test it.
- **Phase B changes NOTHING about preview/production policy.** A self-service PR inherits whatever the existing rules say for its content: classifier-clean low-risk SQL may use the #2758 ephemeral path; anything else previews as usual. No new carve-out is created here.
- **Scheduled jobs never write.** The hygiene report holds read-only permissions and files no issue, comment or label — the same discipline as the `Author Lane Abandonment Audit` workflow. Writes stay with sessions that can be held accountable.
- **`NON_STRUCTURAL_EXITS` and the AGENTS.md §0.0-C prose table must change in the same pull request.** Their agreement is a stated invariant of §0.0-C.

**Open (implementer judgment, with criteria):**

- The exact statement whitelist inside the classifier (§ Step B1 proposes a starting set; tighten freely, loosen only with a fixture proving why the case is safe).
- Hygiene report cadence (daily is the proposal; hourly if it proves too stale).
- Whether the merge-caller question (Step B3) needs any change at all before #2530 lands — decide after reading the dispatch model, defaulting to "change nothing."

## 9. The plan

### Phase A — queue hygiene (no gate behavior changes; safe to land independently)

**A1. Label the unlabelled issues.**
For each issue the audit prints under `UNLABELLED ISSUES` (2026-09-17 reading: #3193, #3191, #3187, #3181, #3174, #3149, #3148, #3146, #3125, #2530 — re-derive, the list will have moved):
1. Read the issue body. If it lacks a `db-work-scope` fenced block, write one with the authoring session if reachable, else draft it from the issue's own text and note that you did.
2. Apply the label: `gh issue edit <n> --repo u2giants/shared-db --add-label db-work`.
Order matters: scope block first, label second — the label is what makes the issue visible to admission, so an unverified label is a silent misroute. #2530 already carries a valid block (`work_type: documentation`, `route: repo-maintenance`); it needs only the label.
*You'll know it worked when:* a rerun of `--queue-audit` prints no `UNLABELLED ISSUES` block (the audit may still exit 2 for other reasons — judge by the block, and fix only what the block names).

**A2. Close out expired claim #3089.**
The audit's `EXPIRED AUTHOR LEASES` block names claim #3089, lane 2, "PR merged, queued none". Expiry never releases object protection (`table plm.production_lane_canary` stays locked), so the claim must be explicitly closed. Use the guarded path — never hand-edit the issue body's fenced blocks: run `node scripts/manage-migration-author-lanes.mjs --recover-expired-claim-from-pr` for the claim (confirm the exact subcommand spelling and required arguments against the script's usage block before running; the release path enforces owner match, no open PR on the branch, and the author mutex), finishing with the release. If the guarded command refuses, STOP and write the refusal verbatim into the tracking issue — a refusal here is a safety result, not an obstacle.
*Gate:* the audit's `EXPIRED AUTHOR LEASES` block no longer lists #3089.

**A3. Ship the `Queue Hygiene Report` workflow.**
New file `.github/workflows/queue-hygiene-report.yml`, copying the `domain-ownership.yml` shape: `on: schedule` (daily) + `workflow_dispatch`, `permissions: contents: read, issues: read` and NOTHING else, one job that runs the read-only queue audit and prints its `UNLABELLED ISSUES`, `EXPIRED AUTHOR LEASES`, and `NOT ORCHESTRATOR WORK` sections to the job summary. It must not comment, label, or file anything. Add a comment in the file stating that write permissions are deliberately absent and why (scheduled-job no-write precedent).
*Gate:* one green `workflow_dispatch` run; the workflow's permissions block in the merged file shows read-only.

### Phase B — the self-service additive lane

**B1. The boundary classifier.**
New `scripts/check-self-service-additive-lane.mjs` plus `scripts/check-self-service-additive-lane.test.mjs`. Input: the pull request's changed files and the text of any new `supabase/migrations/*.sql` files. Verdict `pass` ONLY when every rule holds; any miss, any parse doubt, anything unrecognized → `refuse` with the named reason (fail closed, same philosophy as the #2758 classifier):
- Non-migration changes are documents only (Markdown/docs/skill text) — no workflow, script, or `.github` changes ride along.
- Every migration file is NEW (its version does not exist on `main`).
- Lexed top-level statements are ONLY: `create table`, `create view`, `create function`, `create index`, `create sequence`, `create schema`, `create policy` / `enable row level security` ON an object this same file set creates, and `grant` ON such a new object. One `create or replace` of an object that already exists on `main` → refuse.
- Every created object's schema is in `{crm, pim, dam}` or a brand-new schema created by the same file set. Anything in `plm`, `api`, `core`, `public`, `ingest`, or `storage` → refuse.
- Zero data statements (`insert`/`update`/`delete`/`merge`), zero `alter`, zero `drop`, zero `truncate`.
Write the tests dirty-first (the `check-github-transport-conformance.mjs` discipline): known-dirty fixtures — a `core.*` create, an `alter` on an existing table, a sneaky `create or replace function` shadowing a live one, a data backfill, a grant on an existing schema, a workflow file riding along — each asserted to REFUSE, before any fixture asserts a pass.
*Gate:* `node --test scripts/check-self-service-additive-lane.test.mjs` green offline.

**B2. Admit the route.**
In `scripts/manage-migration-author-lanes.mjs`: add route `self-service-additive` to the admission machinery so `--claim --admit-issue <n>` accepts it and reserves version + objects exactly as structural work does, while `--queue-audit` excludes it from the orchestrator's dispatch/refill list and prints it in its own section (the way `OUTSIDE ORCHESTRATOR — OWNED BY REPO SESSION` is printed). Update `NON_STRUCTURAL_EXITS` and the AGENTS.md §0.0-C prose table in the SAME pull request, and add a small sync test asserting the two agree (mirror whatever existing test pattern keeps such tables honest; if none exists, create `scripts/check-non-structural-exits-sync.test.mjs` reading both sources).
*Gate:* sync test green; audit shows the section; a claim made through the route on a dry-run issue succeeds and its objects lock.

**B3. CI guard + the merge-caller decision.**
New `.github/workflows/self-service-lane-guard.yml` (own workflow, NO `paths:` filter, `tools-offline-tests.yml` discipline) running the B1 classifier on any pull request whose issue's `db-work-scope` declares `route: self-service-additive`; refusal fails the check with the classifier's named reason. Wire the B1 and B2 tests into `tools-offline-tests.yml` (explicitly — the PR #331 lesson).
Then the judgment call: determine who may dispatch the guarded merge for such a pull request (read `.github/workflows/guarded-migration-merge.yml`'s triggers and any caller checks). If the authoring session can already dispatch it, document that. If it cannot, DEFAULT TO CHANGING NOTHING: the interim state is that any session the workflow already authorizes presses merge, and #2530's native queue replaces the hop entirely. Write the decision and its reasoning into this plan's §8 (move it from Open to Locked with the date). Never weaken a caller check to save one hop.
*Gate:* guard refuses a fixture out-of-boundary PR in a dry run; the merge-caller decision is written down.

**B4. Document the lane.**
AGENTS.md: extend the §0.0-C exit table with the new route (one row, prose matching `NON_STRUCTURAL_EXITS` exactly) and add a short subsection under §4's operative summary: what qualifies, what the authoring session does (claim with `--admit-issue`, author in a worktree, open the PR declaring the route, let the guard + reviewer draw run), and what is permanently excluded. Keep it tight — AGENTS.md has a size ceiling it has fought before. Update BOTH skill copies (`shared-db-change` in `~/.zcode/skills/` and `codex-shared-db-change` in `~/.agents/skills/`) with the same lane description, and add a memory entry: "read the plan's STATUS table first — do not re-derive."
*Gate:* a cold fresh session, given only AGENTS.md and the skill, can correctly execute a qualifying change and correctly refuse a non-qualifying one.

### Phase C — zero-touch wait chain for classifier-clean production

**C1. The hop table.**
Read `scripts/dispatch-production-apply.mjs`, `scripts/production_business_risk_gate.py`, `scripts/test_automatic_qualification_route.py`, and the dispatching workflows. Write `docs/agents/ephemeral-route-hop-table.md`: for every hop between "merge completed" and "production apply finished" on the #2758 ephemeral route — who or what performs it, what evidence it consumes, whether it is manual, and if manual, exactly why. Counts and states cited as the command that produces them (§4.3 ruling), never pasted numbers.
*Gate:* the table is merged and every hop has a named actor.

**C2. Automate pure mechanics only.**
For each manual hop: if it is evidence lookup/transcription with no judgment (e.g., copying a run id), automate it the way the existing automatic-qualification route works, with tests in the style of `scripts/test_production_preview_skip.py`, preserving every refusal. If the hop is a guard judgment (owner decision, business-risk conclusion, target proof), it STAYS manual and the table says so. The ordinary #2758 path's constraint stands: no manual production command, no manual workflow dispatch, no bypass — automation extends the existing narrow path, it does not add a second one.
*Gate:* each automation lands with tests; the hop table updated in the same pull request; zero refusal semantics removed (each refusal still fires on its fixture).

### Phase D — landing

Update this plan's STATUS row after every landed step (the doing session owns de-staling, `session-docs-update` gate). When the tracking issue closes, retire the paired handoff file in that same change (§2.1-H: finished files are deleted, never marked done).

## 10. Tests required

- `scripts/check-self-service-additive-lane.test.mjs` — dirty-first fixtures per Step B1 (each named refusal case listed there is one test), then pass fixtures (new `dam.*` table + its policy + its grant + an index on the new table; a new schema + one table in it).
- `scripts/check-non-structural-exits-sync.test.mjs` (Step B2) — parses `NON_STRUCTURAL_EXITS` and the AGENTS.md §0.0-C table; refuses on drift.
- Step C2 automations: tests mirroring `scripts/test_production_preview_skip.py` (offline, fixture-driven, refusal-preserving), wired into the same workflow that runs its siblings.
- Existing suites that must stay green: `tools-offline-tests.yml` (`node --test tools/*.test.mjs` + its explicit scripts list), the `SQL migration guards` job (`scripts/check-sql.test.mjs`, `scripts/check-applied-migration-edit.test.mjs`), and the lane script's own tests wherever they run today — find the workflow that runs them before touching the script (Step B2), not after.
- Every new test file is explicitly wired into a workflow in the same pull request that adds it.

## 11. Constraints, standing rules, and gotchas

- **Worktree-only (§2.1-W):** every executing session works in its own `git worktree` cut from `origin/main`; nobody branches or commits in the shared checkout `C:\repos\shared-db`. Remove only your own worktree.
- **Task gates:** each session declares its class before work (`ai-task-gates start --class <class>`). Phase A1/A3/D are `prose` or `code`; Phase B/C sessions re-declare and expect escalation to the protected `shared-db` class — satisfy its proofs; acknowledgement flags do not bypass protected classes.
- **Docs-only vs code PRs:** this plan file's own PR is documents-only (rule 18: no reviewer required; merge promptly once checks pass). Phase A3/B/C pull requests are code — they take the full path including independent review where required (scripts/CI work needs one; anything touching the lane script's admission logic should be treated as reviewer-safety-adjacent and get two).
- **Never edit an applied migration, never reuse a timestamp (§4 rules 4–5)** — Phase B creates none, but its fixtures must not either.
- **Never weaken required checks** (also a #2530 constraint).
- **Scheduled jobs hold read-only permissions and write nothing** (A3); the abandonment-audit precedent is the citation if challenged.
- **The label is an admission trigger** (A1 order: verify scope block, then label).
- **Public repo (§6.14):** no personal identifiers, no secrets by value, licensed data stays out. Skills reference 1Password by vault + item title only (none expected here).
- **§4.2 connection proof** applies only if any step ever touches a database — none is planned; if one appears, stop and re-scope.
- **AGENTS.md size ceiling:** keep the §0.0-C addition to one table row plus a short subsection.
- **Concurrent sessions:** `origin/main` moved twice during this plan's authoring; always `git fetch origin` and re-derive queue state rather than trusting this document's counts (§4.3).

## 12. Access and environment

- **GitHub:** `gh` CLI authenticated (owner account). Issue/PR/workflow writes go through it; reads via `node scripts/gh-read.mjs api …` inside workflows (§5.2-B: workflows never make bare `gh api` reads; Node gates use `scripts/lib/github-transport.mjs` + `scripts/lib/github-tree.mjs`).
- **Worktree:** `C:\repos\shared-db\.claude\worktrees\<slug>`; branch `zcode/…` or `codex/…` per session tool; cut from `origin/main` after a fresh `git fetch origin --prune`.
- **Running tests locally:** `node --test scripts/<file>.test.mjs` for Node; Python gate tests follow the invocation used by the workflow that wires them (check the workflow, don't guess).
- **Secrets:** none required. No Supabase tokens, no `PREVIEW_PROJECT_REF` reads, no ephemeral check runs except as read-only evidence in Phase C's audit.
- **Local checkouts of skills:** `C:\Users\ahazan\.zcode\skills\shared-db-change\SKILL.md` and `C:\Users\ahazan\.agents\skills\codex-shared-db-change\SKILL.md` (machine-local, not in this repo).

## 13. Definition of done, risks, open questions

**Definition of done:** A1–A3, B1–B4, C1–C2 landed on `main` with CI green and tests wired; `--queue-audit` shows the self-service section with the sync test guarding table agreement; the hop table exists with every remaining manual hop justified; AGENTS.md + both skills + memory updated; this plan's STATUS current at every merge; the tracking issue closed with evidence links; the paired handoff deleted in the closing change. Success is measured live, not historically: rerun the queue audit and `gh pr list` after Phase B has been in use — the test is that a qualifying app change merges without any orchestrator-session turn, which `--queue-audit`'s self-service section should begin to show.

**Risks and rollback:** the classifier false-accepting an out-of-boundary change (mitigation: fail-closed lexing, dirty-first tests, the boundary is schemas + statement kinds, both checkable mechanically; rollback: revert the route from `NON_STRUCTURAL_EXITS` — refusals return instantly since fail-closed is the default); route-table drift between script and AGENTS.md (sync test); A1 labelling mistakes (scope-block-first order; a wrong label is removable and the audit re-runs); workflow write-permission creep (review the permissions block; the file's own comment states the invariant); merge-caller temptation in B3 (default is change-nothing; #2530 owns that hop). Every phase is independently revertible by pull request revert; none writes to any database.

**Open questions:** (1) the exact statement whitelist edges in B1 — decided by fixture evidence during implementation; (2) whether Phase C finds the ephemeral route already zero-touch apart from load-bearing guards — an acceptable outcome is a hop table whose every manual hop is justified, with no code change at all; (3) whether, after #2530 lands and Phase B is proven, a second orchestrator session is still wanted at all — separate decision, deliberately not this plan's.

---

## Self-audit (mandatory, per the implementation-plan standard)

1. **Could a brand-new session execute this without asking anything?** Yes — §9 names every file, command and subcommand (with the instruction to confirm spelling against the script's usage block rather than trust this page), §5 gives the current-state inventory with paths, §12 gives access and invocation details, and every step has a verification gate. The two deliberately judgment-shaped spots (B3's merge-caller decision, C2's automate-or-document) state their criteria and their safe default.
2. **Does it carry everything the planning session knew?** Yes — the rejected approaches (§7) include the second-orchestrator option and why it was sequenced out, the auto-label bot, reviewer reduction and boundary creep; §6 records the root cause (attention, not capacity) and the #2530-blocking discovery; §3 records the live evidence with the commands to re-derive it (§4.3 discipline).
3. **Is the ultimate goal clear enough to steer by when a step is wrong?** Yes — §1 states the outcome and the non-negotiable safety floor with the explicit "the floor wins — stop and flag it" instruction, and §8 separates locked from open decisions with dates and rationale.
