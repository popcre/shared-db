---
issue: 4421
status: BLOCKED
owner: codex/rls-performance-plan
---

# RLS permission-check performance repair handoff

## 0. Business decisions only the owner can make

None. Preserve existing access exactly. Already settled October 18, 2026 EDT: Albert requested a plan for the entire warning family after a wider investigation and timing measurements. This planning request does not start database remediation. Technical review, access repair and implementation mechanics belong to the implementing AI, not Albert. If new business questions arise, consolidate them once; do not ask for technical approval.

## 1. What this application is

POP applications share Supabase PostgreSQL. Canonical structural source is popcre/shared-db; no application runtime lives here. Production API observed: https://qsllyeztdwjgirsysgai.supabase.co . Preview comes from current repository variable PREVIEW_PROJECT_REF, never a historical literal. CRM, DAM, PM/PIM and DesignFlow depend on this structure.

## 2. Session goal and trigger

Supabase flagged assets insert policy for repeated auth evaluation. Albert requested wider inspection, measured speed difference, then a self-contained implementation plan. The plan covers 69 policies across 49 tables while retaining existing permissions.

Read [the plan](../plan_rls_request_constant_checks.md) first, especially STATUS. Portable link: [plan_rls_request_constant_checks.md](https://github.com/popcre/shared-db/blob/codex/rls-performance-plan/plan_rls_request_constant_checks.md).
Measured evidence and exact 69-row inventory: [baseline](https://github.com/popcre/shared-db/blob/codex/rls-performance-plan/docs/verification/rls-initplan/2026-10-18-baseline.md).
Owning issue: https://github.com/popcre/shared-db/issues/4421 . Parent broader program: https://github.com/popcre/shared-db/issues/2326 .

## 3. Current state

October 18, 2026 EDT: planning/evidence only. No implementation started, no policy changes, migration reservation, structural claim, preview apply or production apply. New plan, baseline and this handoff are being published on codex/rls-performance-plan from upstream 845a92d77b097a8153baf523ec5291b3bcb29b5d. Use the linked PR/issue for actual merged publication status; this file does not claim an unverified merge.

Production read-only inspection and Supabase advisor both found 69 policies / 49 tables: 46 public-admin, 17 owner-uid, four app-access, two packaging/JWT. The plan STATUS intentionally leaves all implementation steps open. Supabase MCP reads and gh worked; preview/write access not demonstrated. No background worker is executing this plan.

Publication blocker verified October 18, 2026, 10:35 AM EDT: [PR #4423](https://github.com/popcre/shared-db/pull/4423) contains the committed/pushed plan. Repository classification says “all 5 changed file(s) are lightweight prose documents”, but installed task gate escalates the plan/router paths to reviewer-safety and refuses ship without an assigned independent exact-head report. Canonical allocator refused “nonclosing maintenance binding refused: one current keyed canonical evidence pair is required”. No reviewer was assigned and no review ran. The repository documentation route did not require such a pair; publishing one retrospectively would contradict the pre-work guarantee. Do not fabricate it. This session owns resolving supported publication; a successor must re-read the current gates or take a genuinely fresh prospectively contracted publication route without claiming this prior plan was written under that contract.

## 4. Failed or rejected approaches

UID-only wrapping improved assets expression median by only 7.3%; complete request-constant permission wrapping improved 97.2%. These are controlled expression measurements, not end-to-end RLS or app speed. Elevated tests do not prove client access. Never use broad regex rewriting, wrap row-dependent ownership predicates wholesale, consolidate policies, change grants/helper bodies, disable RLS, or run write benchmarks on production.

Task class “read-only” was rejected as unknown; investigation used shared-db. Plan publication initially declared prose, then redeclared reviewer-safety when the installed gate required it. The Claude helper invocation was refused before contact because registry state is absent. An initial allocator attempt also refused ambiguous Refs issue binding; PR body now has exactly Refs #4421, with parent #2326 as a URL. The next allocator attempt refused the missing prospective keyed evidence pair, as recorded in §3. No bypass or fabricated evidence was used. All durable evidence is in the tracked baseline, not a temporary report. See plan §7 for the complete rejected list and reasons.

## 5. Root causes and key findings

The costly permission-table helper can still run per row after wrapping auth.uid() alone. Prefer wrapping the complete proven request-constant helper; owner user_id comparison must remain per-row.

Anchors at planning base: [legacy helper lines 5170–5180](https://github.com/popcre/shared-db/blob/codex/rls-performance-plan/supabase/ci-bootstrap/010_pre_adoption_baseline.sql#L5170), [legacy assets insert line 6635](https://github.com/popcre/shared-db/blob/codex/rls-performance-plan/supabase/ci-bootstrap/010_pre_adoption_baseline.sql#L6635), [style-guide policies lines 773–788](https://github.com/popcre/shared-db/blob/codex/rls-performance-plan/supabase/migrations/20260723170000_popsg_file_tags.sql#L773), [packaging policies lines 30–62](https://github.com/popcre/shared-db/blob/codex/rls-performance-plan/supabase/migrations/20260709144500_core_packaging_type.sql#L30).

Two distinct role systems exist (public and app); do not unify overloads/enums. Packaging transitive JWT/profile helpers need qualification before caching. Fingerprints detect drift, not custody. Live catalog wins over historical migration or bootstrap content. Raw timing values and reproducible SQL are in the baseline.

## 6. Exact next steps

1. Open plan STATUS and §§1–13; fresh upstream isolated worktree, current rules, #4421/#2326/open claims/PR refresh. Gate: every baseline policy has a fresh disposition.
2. Implement plan Step 1 admission, exact-object claims, immutable work contract and new version reservation; planning owns no structural authority. Gate: current write set exactly covered.
3. Execute Steps 2–4: real role-enforced baseline, adversarial fixtures, expression-only forward ALTER POLICY, preview, timings, consumer proof and one allocator-assigned exact-head review. Gate: metadata and allowed/denied behaviors match.
4. Execute Steps 5–7: guarded merge, supported merged-main rehearsal/production lane, live proof and final reconciliation. Gate: immutable ledger/catalog/test/consumer acceptance; same issue remains open until all pass.

Each step's concrete file targets, dependencies, test names, commands/current runner references, thresholds and rollback are in plan §9–§13. No chat reconstruction is needed. Read downstream phases again at each context cut.

## 7. Constraints and gotchas

Use claim-first structural route; never inherit parent #2326's repository-maintenance scope or old orchestrator text. One independent exact-head review, current task gates, reserved forward versions, preview/merge/production exclusive lanes, proof before writes, and supported automatic promotion only. Production SQL fixture/write benchmarks prohibited. Preserve implicit WITH CHECK, OR/restrictive semantics, grants, policy metadata and error behavior. Preview/production diverge both ways. Secret/license data stays protected; public artifacts contain metadata and synthetic values only. Sign every GitHub post with actual chat ID/machine. Human-facing clocks are EST/EDT.

Keep broader program open. No subagents were spawned, so no delegated-agent custody exists to transfer.

## 8. Access and environment

Verified planning access: Supabase production read-only MCP and authenticated gh for popcre/shared-db. Unknown: preview credentials/leases, production promotion eligibility and consumer test accounts. Re-verify at execution. 1Password vault vibe_coding contains references named in plan §12; no secret values in these documents. Read the secrets skill before handling values and serialize retrieval. Current runner and supported commands are in [development](https://github.com/popcre/shared-db/blob/codex/rls-performance-plan/docs/development.md) and [credential runbook](https://github.com/popcre/shared-db/blob/codex/rls-performance-plan/docs/agents/runbooks-credentials-cli-and-gotchas.md).

## 9. Risks and open questions

Technical open items (implementer-owned, October 18, 2026 EDT): fresh collisions, transitive helper stability, preview parity, consumer mapping, real role fixture coverage, actual workload improvement and safe live application write proof. No business choice is pending. Plan §13 gives criteria and recovery through a new forward migration. No implementation item is complete. Retire this file only when #4421's outcome is fully proven and its obligations are carried or finished; leave the root HANDOFF.md untouched.

Handoff audit: all sections 0–9 present, goal/dead ends/evidence/custody/next gates/access/uncertainty retained, no hidden owner question, portable links included, plan backlink present.
