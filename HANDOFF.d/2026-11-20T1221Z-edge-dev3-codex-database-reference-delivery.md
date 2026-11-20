---
issue: 6877
status: OPEN
owner: codex/01a1f55c (documentation closeout; Uma owns DesignFlow landing)
---

# Database reference delivery handoff

1. **Goal.** Make the shared database design easy for future AI sessions to find, then verify each app links to it.
2. **Delivered.** [Shared-db #6877](https://github.com/popcre/shared-db/pull/6877) merged. The [canonical reference](https://github.com/popcre/shared-db/blob/main/docs/database-design-and-schema.md) is on main and linked from its [agent guide](https://github.com/popcre/shared-db/blob/main/AGENTS.md). The [PopCRM README](https://github.com/u2giants/popcrm-web/blob/main/README.md) was published and verified. [PopDAM #1234](https://github.com/u2giants/popdam3/pull/1234) passed checks and merged. [DesignFlow Tracking #219](https://github.com/popcre/designflow-tracking/pull/219) merged.
3. **Environment.** Documentation only. No schema or data changes were applied to preview or production, and there were no migration reservations or releases to schedule.
4. **Pending.** The links were pushed to DesignFlow sandbox and are in PRs to develop: [Frontend #620](https://github.com/popcre/designflow-frontend/pull/620), [Backend #476](https://github.com/popcre/designflow-backend/pull/476), [Item Master #275](https://github.com/popcre/designflow-item-master/pull/275), [BFF #100](https://github.com/popcre/designflow-bff/pull/100), and [Data Syncing #169](https://github.com/popcre/designflow-data-syncing/pull/169). These were open at wrap-up. Some contain unrelated work. Recheck their diffs and states before drawing conclusions.
5. **Ownership.** Uma owns the DesignFlow develop merges. No separate successor chat was started. Codex did not claim structural work in this chat. Keep any unmerged source and unrelated sandbox history.
6. **Next action and proof.** Check the five PRs. Once each lands, open that repository's README on develop and verify the link resolves to the published reference on shared-db main. Verify the PopDAM agent guide on main too. If a PR closed without the link, first check whether a successor already delivered it; otherwise use the DesignFlow shipping route. No live app deployment is needed to prove a repository link.
7. **Dependencies.** DesignFlow requires its normal review and merge path. The merged shared-db PR is the documentation evidence card. [#6208](https://github.com/popcre/shared-db/issues/6208) separately tracks ColdLion work. The two Princess changes were saved on Style moves in Albert's Dropbox workbook; ColdLion completion was not checked. No email to Uma is needed, per [#4706](https://github.com/popcre/shared-db/issues/4706#issuecomment-7019958704).
8. **Failed routes.** The initial shared-db checks failed an unrelated UPC permissions test; incorporating the current main fix preceded the merge. DesignFlow app agent guide changes were declined by the protected work classification; the links shipped in README files. PopCRM initially rejected a stale push; the commit was reconciled and then pushed.
9. **Drift and audit.** PR state and link presence may change. The URLs identify all evidence and next actions; no local checkout, secret, or transcript is needed. Completion is verified by the canonical document plus the link on each app's target branch.
