# Handoff — ColdLion automatic order intake plan

- **Date:** 2026-09-17T14:40Z · **Agent:** ZCode (GLM) · **Session:** live ColdLion
  order-intake investigation + planning
- **Revised 2026-09-17 (later same day):** externally audited by Qwen (`qwen3.8-max`,
  read-only review, verdict REJECT on v1); every load-bearing finding was independently
  re-verified against the repository and folded into the plan. Audit record:
  `.ai/reviews/qwen-order-intake-plan-audit-5a2fd8b6ac9b199946cc14b3895d00b870e0746a04180c4f5ef58073e9fe6c4f.md`
  (copy; session-resumable clone at `C:\repos\shared-db-qwen-audit`).
- **Revised again 2026-09-17/18:** audited by Grok 4.6 (read-only, verdict "not ready" on v2;
  1,826,087 tokens, $0.56) — including the 1:N ruling's design consequences and a correction
  of one Qwen finding (sealed landing tables DO grant `service_role`). Record:
  `.ai/reviews/grok-order-intake-plan-audit-v2-20260918T003208Z-368754.md`. All findings
  re-verified and folded in.
- **Revised a third time 2026-09-18:** audited by Muse (read-only, verdict "not ready" on v3;
  4 blocking + 9 major). Its headline finding was an authority-file defect: the business-rules
  topic still carried the pre-2026-08-31 "bare list" description of `/orderHistory` — fixed in
  the authority file itself (superseded paragraph, live re-verified paged contract). Record:
  `.ai/reviews/muse-order-intake-plan-audit-v3-20260918T011029Z-606747-3631.md`. All findings
  re-verified and folded in. Note: mid-session the canonical repo advanced two commits
  (bf16ed5a → 079fed75, another agent's merges); the audit clone has since been refreshed to
  079fed75.

## What exists now

The automatic-order-intake implementation plan is written and registered:
[`plan_coldlion_order_intake.md`](../plan_coldlion_order_intake.md).
**Read its STATUS table first — do not re-derive or re-plan.** Every step is
`⬜ open` as of 2026-09-17 (C0 is ✅ ruled: one sales order → many production orders); a fresh
session starts at **Step 0** (land the docs).

## What the plan builds on (already settled, do not re-litigate)

All business rulings live in
[`docs/business-rules/erp-orders-and-source-meaning.md`](../docs/business-rules/erp-orders-and-source-meaning.md),
section *How a new order enters the system (OrderList intake)*: the intake workflow, the
Settled automation ruling (intra-day poll, unsealed current-window on our side, JamieLynn
stays manual), the routing-code decode (Order Type + Ship To = `warehouseCode`), POE vs DDP
definitions, the forward-horizon ruling, and the `shipPortCode` mapping decision. Those
business-rules edits are **uncommitted** in the working tree at handoff time, together with
`application-map.md` and `master-data-access.md` — review and commit them with the plan's PR
or a docs-only PR.

## Where the evidence is

- Live-probe findings (window filter keys on start date; poNumber zero-padding; no created
  timestamp; routing vocabulary; case pack at item grain; `/prodtracking` port slots):
  the business-rules topic above, all dated 2026-09-17.
- Canonical contract and reconciliation design:
  [`docs/app-migration-notes/popdam-order-list.md`](../docs/app-migration-notes/popdam-order-list.md)
  and migrations `20260810010000` / `20260810060000` / `20260831045020`.
- Sealed-window sync that the intake must never touch:
  [`tools/coldlion-landing/sync-history.mjs`](../tools/coldlion-landing/sync-history.mjs)
  (read its header comment) and
  [`tools/coldlion-landing/lib/load-window.mjs`](../tools/coldlion-landing/lib/load-window.mjs).
