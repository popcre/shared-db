---
issue: 4336
status: BLOCKED
owner: Codex chat 01a1402d-8c8d-79f3-945e-2713340e13d6
---

# OrderList SO Date sorting: preserved source, review-provenance blocker

## 0. Business decisions only the owner can make

None. Albert authorized fixing user sorting by SO Date and taking over the crashed Claude claim. Do not ask him for technical approval or create another application-need/live-proof issue. The technical blocker below remains owned by this Codex chat until a qualified recipient explicitly accepts it.

## 1. Application and repositories

PopDAM is the internal artwork manager at https://dam.designflow.app. Its OrderList page reads bounded blocks from the shared Supabase backend. App source is [u2giants/popdam3](https://github.com/u2giants/popdam3); shared structure belongs to [popcre/shared-db](https://github.com/popcre/shared-db). The schema change must complete the governed shared-db path before dependent app code is changed. No durable host changes belong here.

## 2. Goal and acceptance

Albert requested: "pull the latest repo. OrderList can't be sorted (by a user) by SO date. make that possible" and "don't file the issue and stop. FIX IT YOURSELF!" He later said "that session crashed. take over the claim by force". One existing work card: [#4336](https://github.com/popcre/shared-db/issues/4336).

Success means a normal user can sort the complete filtered result set in both directions by SO Date; missing/conflicting dates remain blank and last; line-ID ties are stable; Find uses the same ordering; ordinary paged loading remains fast. SO Date remains unavailable as a filter. The existing 12-month window and its fallback rule are outside scope. Live browser proof is required before closing the work.

## 3. Current verified state

Source is committed and pushed in [PR #4360](https://github.com/popcre/shared-db/pull/4360), branch `codex/4336-orderlist-so-date-sort`, head `9c088585ab77abb2749a0352e6b81af083cbcc36`. Implementation head is `7345f6f1dd996a6f13e391fdb3449d01cd70e580`; the following commit adds generation-8 evidence. The worktree is clean and must be preserved. Current merged main was `1c731f87ee8caf5ca94099485f77e49ca6290693`, verified October 15, 2026 around 8:31 PM EDT; refresh before reuse.

Owned change files at the preserved head:

- [Migration 20261015201243](https://github.com/popcre/shared-db/blob/9c088585ab77abb2749a0352e6b81af083cbcc36/supabase/migrations/20261015201243_orderlist_so_date_sort.sql): exact-source, NY-calendar-date helper; appended view sort key; Find sort-only allowlist.
- [Behavior harness](https://github.com/popcre/shared-db/blob/9c088585ab77abb2749a0352e6b81af083cbcc36/scripts/test_order_list_find_position.py): 18 position cases, four independent ranking comparisons, exact-line binding/company/date/auth/RLS/service-role checks; zero skipped on the session-owned disposable PostgreSQL container.
- [SQL contracts](https://github.com/popcre/shared-db/blob/9c088585ab77abb2749a0352e6b81af083cbcc36/supabase/tests/dam_order_list_sales_order_date_sort.sql): catalogs, privileges, actual view/Find fixtures, ordinary projection/count plans. Latest source adds VERBOSE plans and all-ordinary-column 500-row default-Start-Ship blocks at offsets 0, 500, 1000.
- [Generation 8 contract/report](https://github.com/popcre/shared-db/tree/9c088585ab77abb2749a0352e6b81af083cbcc36/.agent/work/4336/8): immutable published contract `refs/db-contracts/4336/8`, hash `38ae544a6e7869ee42b6da53a4fcf8c290b8da13b0b0ac77422c9548b36c5409`. Report explicitly lists pending acceptance. Its schema-mandated `ready-for-merge` label does NOT discharge preview/merge acceptance.
- Registered [sidecar](https://github.com/popcre/shared-db/blob/9c088585ab77abb2749a0352e6b81af083cbcc36/scripts/production-verification-sidecars/20261015201243.json), migration hash unchanged, dynamic-SQL marker line 337.

Local static SQL guards, 82-sidecar guard, diff whitespace check and disposable helper/Find harness passed at implementation head. Live-ledger B2 was skipped because no shared ledger was configured. Prior head `035ab8c50787076c3f98660f9736502e7bb94da7` passed all required CI, including the ephemeral database suite. Fresh-head CI was still running at the last check; consult PR checks rather than inheriting a pass.

**Preview: no persistent apply by this Codex session. Production: no writes, migration, merge, or deployment by this session.** Shared preview identity/ledger have not been freshly read. App work is untouched: the preserved clean app worktree is at `94b41b745fc18d8defbef6295cc0214d880145a2`; do not treat that old source as current upstream.

[Claim #4359](https://github.com/popcre/shared-db/issues/4359) retains exact objects `view api.dam_order_list`, `function dam.orderlist_sales_order_received_date`, `function public.find_dam_order_list_row`, permanent version `20261015201243`. Native stop-author succeeded at 8:44 PM EDT, with capacity relinquished and ready receipt `refs/db-author-handoff-ready/4359-20261015201243-db9b9d78476e64d67210811e`, commit `de649101d554ac73429db32f7698c4f6d0d0a5b9`. This is stopped ownership, NOT release of object/version protection. Read the claim for exact original custody; no machine path is portable authority.

## 4. Attempts that did not work

1. Original Claude session was `claude-chat-250902fb-e85f-45d3-a62c-9c18cb217d1e@hetz`; its prior claim/version were retired during the authorized takeover. Do not reuse `20261015154023`.
2. Earlier StepFun output had multiple parseable verdict lines and was correctly voided. Muse requested revisions; source checks, exact-line binding/auth checks, real CI fixtures and a count-plan assertion were added across subsequent heads. Do not recover an approval from voided prose.
3. At old head 035, DeepSeek durable refusal [e483296f](https://github.com/popcre/shared-db/commit/e483296f253c788677d665e8db3c6bc7da911630) treated absent preview proof as a merge blocker despite finding no code defect blocking preview. GLM slot 2 then explicitly cleared preview in [07f7de7e](https://github.com/popcre/shared-db/commit/07f7de7e70a7f8e47d72471350c9f3466bee1d6f). A later approval does not erase an existing durable refusal at the same head. The exact-head checker refused 035 and required new source plus fresh review. Continuing DeepSeek through the old draw also refused: its reviewer lease had ended.
4. Old governed tooling called provider wrappers without provider-neutral lifecycle evidence. `ai-task-gates check --before database --reviewer-approval <GLM report>` refused: not a lifecycle-recorded independent exact-source approval. Main PR #4308 is now merged and repairs this through the `ai-review` front door. The preserved branch includes that upstream repair.
5. A supplemental `ai-review glm final-check --implementer codex` started at 035. Its result became stale when source advanced; terminal result was source-head-mismatch. It authorizes nothing. Do not import or manually finish that lifecycle.
6. **My implementation mistake:** I combined the bounded-plan test improvement with merging current main into merge commit `7345f6f1`. The paid-review source-provenance guard permits canonical upstream merges and separate authored commits, but rejects authored source mixed into an upstream merge. Current-head reviewer assignment stopped BEFORE provider launch with `REFUSED: review budget Git provenance refused: review budget noncanonical or foreign merge refused`. The source remains preserved; repeatedly assigning reviewers cannot repair this. Do not force-push, remove safeguards, reset review accounting with a new PR, forge a paid-start/ref, or weaken this guard.

## 5. Findings and governing rules

The current blocker is branch provenance, not a database execution failure. See [the exact guard](https://github.com/popcre/shared-db/blob/1c731f87ee8caf5ca94099485f77e49ca6290693/scripts/lib/lanes/review-circuit-breaker.mjs#L450) and [recovery policy](https://github.com/popcre/shared-db/blob/1c731f87ee8caf5ca94099485f77e49ca6290693/docs/agents/review-recovery-policy.md). Its supported conservative fallback does not cover noncanonical authored merges. No policy-compliant built-in recovery for this particular pushed history was identified; this uncertainty is the immediate technical work, not a reason to invent a bypass.

The stage sequence for this issue is: exact-source review clearance, clean gated pre-merge preview dry-run/apply and behavior proof, guarded merge, then merged-main rehearsal before production promotion. Both the issue and merge checklist require pre-merge preview acceptance. Earlier generation assumptions incorrectly deferred all preview proof until after merge; generation 8 corrects them. Normal post-merge rehearsal documentation remains separately binding.

## 6. Ordered continuation and gates

1. Re-read this issue, current PR/claim/ready receipt and latest merged rules. Refresh source refs; preserve the existing clean source and stopped custody. Gate: all source/version/claim/readiness hashes match live GitHub.
2. Resolve the exact provenance refusal through a supported technical recovery that preserves every historical paid attempt, original code and the standing no-force-push rule. No implementation may proceed merely because a new reviewer would approve. Gate: unchanged guards admit the recovered exact source and authoritative budget accounting; obtain assigned technical review for any recovery mechanism change. If no supported recovery exists, retain the block and state it explicitly.
3. The actual structural recipient adopts the native ready receipt using its own identity before writing structural source. Do not impersonate this chat. Gate: bounded active permission, current exact source, permanent reservation, and object protection all verify through the native tool; check in every ten minutes and before protected actions.
4. Run the fresh exact-source governed review with CURRENT merged tooling, which dispatches through lifecycle-recorded `ai-review`. Use only the allocator's returned provider; do not hand-record verdicts or choose an easier reviewer. Gate: both immutable shared-db APPROVE and recognized lifecycle report exist, no refusal governs that exact source, CI passes.
5. Run the database action gate with the qualified report; use repository preview preparation/selector/lock and workflow inputs, proving the repository variable's current preview target. Gate: dry-run bounded to the intended migration; successful preview apply and actual sort/null/tie/Find parity plus ordinary-load timing at preview scale; record aggregates without licensed rows. Do not dispatch a guessed command or use a remembered preview ref.
6. Complete guarded shared-db merge and separately gated merged-main rehearsal/promotion. Gate: actual ledger/catalog result from the supported workflow, not just source merge or green CI. No manual production push.
7. Only then finish the PopDAM UI: map virtual `sales_order_date` sorting to `sales_order_received_date`; distinguish sortability from filterability; preserve compact select/bounded blocks and Find mapping. Relevant app files are [order-list.ts](https://github.com/u2giants/popdam3/blob/main/src/lib/order-list.ts), [OrderListGrid.tsx](https://github.com/u2giants/popdam3/blob/main/src/components/orders/OrderListGrid.tsx), [useOrderList.ts](https://github.com/u2giants/popdam3/blob/main/src/hooks/useOrderList.ts). Fetch app upstream into its own worktree first. Gate: appropriate tests, review, visual browser proof, normal PR/merge/deploy, and live user-visible asc/desc SO Date sorting across multiple blocks with Find parity.
8. Update the SAME issue with live proof; close only when the full application need works. Retire this handoff only after carrying forward every unresolved obligation and proving delivery.

## 7. Constraints and coordination

No new application-need issue. No direct main push or force-push. No direct shared DDL, manual production apply, blanket credential workaround, weakened guard, new PR to reset budget, or runtime fallback that sorts only loaded rows. Keep business-held source records unchanged. Preserve both worktrees and all other sessions' source. No subagents were spawned. External reviewers are terminal; no reviewer is being reported as currently working. No preview/merge/production exclusive stage was acquired by this session. No business decision or human approval is required.

## 8. Access, environment and closeout checks

GitHub CLI authenticated reads, branch pushes and claim operations worked on `edge-dev3`. The production project is the documented Virginia shared project; preview authority is repository variable `PREVIEW_PROJECT_REF`, not any historical literal. Secrets belong in 1Password vault `vibe_coding`; no secret values were fetched, changed or placed in this handoff. Provider wrappers used managed stores. The PostgreSQL tests used only the session-owned disposable local container, with a task-local psql bridge; the shim was removed after the run. No shared target credentials were needed.

Docs pass: the PR body now says 18 cases and separates pre-merge acceptance from post-merge promotion. No other operating document was changed. Secret sweep: no new credential material encountered. Source/worktrees remain intact. Native capacity cleanup is represented by the ready receipt above, not by a prose promise.

## 9. Open risks, freshness and self-audit

As of October 15, 2026, 8:44 PM EDT: source is not deployed; current-head SQL CI still needed fresh confirmation. Main can advance, claim state can change, and no current preview state/performance is known. The SQL helper scans/probes the full sorted result; scale/timing must be measured before merge. Never infer live success from the local synthetic suite or a bundle SHA.

Self-audit: (1) A new developer has application context, source and custody in sections 1–3 and exact continuation gates in section 6. (2) Sections 4–5 preserve the dead ends, the author's own mistake, the lifecycle repair and the remaining hard refusal. (3) Sections 3 and 6–9 distinguish actual checks, pending acceptance, targets, concurrency and access without secrets. (4) All sections were swept for owner decisions: none require Albert's business judgment; section 0 states that explicitly. All four audit questions pass; the technical recovery remains genuinely blocked, not an invented executable recipe.
