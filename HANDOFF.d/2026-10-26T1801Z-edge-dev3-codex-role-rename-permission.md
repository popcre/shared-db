---
issue: 4832
status: BLOCKED
owner: codex/role-rename-permission-20261026
---
# Production role rename repair

## 0. Business decisions
None. Albert confirmed the reported error occurs on main production. No manual action or technical approval is requested from him.

## 1. Application
DesignFlow supports POP product development. The Angular role editor calls a BFF and the Express/Sequelize backend, deployed on GCP Cloud Run. Production is https://designflow.app/apps/admin/roles; sandbox is https://alsand.designflow.app/apps/admin/roles. Database structural authority is [shared-db](https://github.com/popcre/shared-db/blob/main/AGENTS.md). [Backend operating guide](https://github.com/popcre/designflow-backend/blob/sandbox-albert/AGENTS.md) and [role service](https://github.com/popcre/designflow-backend/blob/sandbox-albert/services/role.service.js) govern the caller. Current live catalog supersedes stale Cloud SQL statements in some app guides.

## 2. Goal
Fix `permission denied for table Roles` when a production administrator renames a leaf role. Success requires delivered database privileges and actual live rename/readback/restoration, preserving membership and other role security.

## 3. Current state
[Issue 4832](https://github.com/popcre/shared-db/issues/4832) owns this outcome and its unchecked live-proof item. [The detailed stop note](https://github.com/popcre/shared-db/issues/4832#issuecomment-6423551074) records every pending delivery stage. [PR 4834](https://github.com/popcre/shared-db/pull/4834) is parked/closed, branch preserved. [Implementation](https://github.com/popcre/shared-db/commit/fb81a313fa08d8742cfa8e27fc1057c340964389) and [evidence](https://github.com/popcre/shared-db/commit/1f85376844d57a3ab3e564c853e499c8b58f7122) are pushed. No independent review, merge, preview apply or production apply occurred. Native ordinary release closed [claim 4833](https://github.com/popcre/shared-db/issues/4833). Reserved version 20261026174936 is permanently spent; resumption requires a new claim/version. No subagents were used. Production was not changed.

[Draft migration](https://github.com/popcre/shared-db/blob/codex/role-rename-permission-20261026/supabase/migrations/20261026174936_dflow_prod_role_rename_update_grant.sql) grants only UPDATE(Name,parent_id,is_active) to designflow_prod_backend_grants. [Contract test](https://github.com/popcre/shared-db/blob/codex/role-rename-permission-20261026/supabase/tests/dflow_prod_role_rename_update_grant_contracts.sql) proves exact column ACL, inherited runtime access, real rename/readback inside rollback, denied kind and DELETE. Local PostgreSQL 16 fixture fails before migration and passes afterward. Static SQL checks pass. Evidence generation 1 explicitly admits draft/local test preceded contract publication; it does not claim pre-draft authorization.

## 4. Failed attempts
The workspace parent is not Git: gates belong inside the actual repository. Use action `deploy`, not `deployment`. App gate baseline must identify actual task scope. Three app release gates refuse generic deploy and require their explicit target manifest; do not bypass them. Six app fetches completed, merging did not: sync is unfinished and not a database-repair prerequisite.

A claim task string without literal #4832 prevented check-in from identifying the work issue; claim title was corrected through ordinary issue title editing. Owner `codex/<uuid>` was accepted initially but check-in's confirmation parser rejects that unsupported form. Do not imitate it. Use `Codex chat <actual UUID> on <actual machine>` from the start. The failed check-in renewed the old lease but did not publish confirmation; the claim was subsequently parked/released natively. Never hand-edit fenced claim blocks.

The grant inspector emits table AND view keys for this single relation. Native claim expansion added its conservative view key and issue scope now names both. Live relation remains a table; SQL was not broadened to satisfy parsing. Exact same-head reviewer assignment first refused missing --admit-issue, then missing conservative key, and finally an occupied acquisition lock. No provider started. Two correct-owner fresh claim attempts failed on governed GitHub GraphQL open-PR inventory HTTP 504. REST reads remained available. Never replace the governed inventory with an improvised mutation path.

Default bundled Playwright browser revision was absent; an installed Chromium executable worked for sandbox read-only inspection. Sandbox admin sign-in succeeded via 1Password/API. Production Chrome opened at login; Microsoft sign-in opened its email-entry popup, without an existing SSO session. Browser autofill briefly filled the production password field; it was cleared without exposing plaintext. No production sign-in or write proof exists.

## 5. Findings
Live production catalogue: designflow_prod_backend_runtime and designflow_prod_backend_grants have SELECT but no UPDATE on dflow_prod."Roles"; row security is false. Sandbox account is postgres with UPDATE, so cannot reproduce this production defect. The service's admin-only save sends Name,parent_id,is_active even for name-only edits; grant those three columns, not whole-table UPDATE. Existing locked-admin checks, unique names and membership IDs remain intact.

The production risk classifier conservatively flags this GRANT under expected_downtime, material_access_change, permanent_data_rewrite_or_loss. Its existing AI risk-acceptance path can accept a substantive allocator-assigned assessment; do not change the classifier or dispatch a manual production command.

## 6. Exact next actions
1. Refresh GitHub and native tooling from current upstream; prove governed open-PR inventory works. Gate: no HTTP 504 and no unknown mutation state. Verify no claims/stages owned by this chat remain; consult native closeout receipt on the same issue.
2. Take a new exact-object claim on issue 4832 with the actual session identity, proper owner label, literal #4832 task and BOTH declared keys. Gate: new unique claim/version with exact body readback. Never reuse 20261026174936.
3. Preserve the parked source, rename its migration to the new reserved version, update its test reference, and publish a successor evidence generation bound to generation 1 before further implementation. Never edit committed generation 1. Account for this handoff as prose in the final inventory. Reopen PR 4834 or create a successor linked to 4832 while preserving prior evidence. Gate: author check-in and all exact scope/source tests pass.
4. Run independent review through allocator and governed runner; pass --admit-issue 4832 to draw. Include --production-risk-classes expected_downtime,material_access_change,permanent_data_rewrite_or_loss and --production-risk-allowlist with the fresh version so its v2 pre-merge assessment covers exact reviewed bytes. Gate: durable exact-head APPROVE and substantive risk block, no ignored refusal. Use observation-week detached review rules where applicable.
5. Complete CI and Guarded Merge, immediately launch qualified merged-main preview through the existing shared-supabase-migrations workflow, and let its protected automatic production lane prove/apply the bounded source. Gate: successful immutable apply receipts plus actual production column privileges; no direct SQL or manual production dispatch.
6. Obtain production sign-in through authorized secure access. The available GUI vault item is sandbox-only; never send it to production or invent/sign a JWT. Prove a reversible leaf rename through the actual application, restore the exact original name, and verify membership/access unchanged. Gate: live proof on issue 4832. Use a test fixture only when authorized and recoverable. No business role assignment is authorized.
7. Complete native claim/stage release and fresh ai-shared-db-closeout-check. Close only after live proof; retire this handoff in the final delivery.

## 7. Constraints
No application code change was necessary. Do not merge DesignFlow application PRs; Uma owns that. Database changes stay canonical, reviewed, claimed, rehearsal-first and target-proved. No guard weakening, broad grants, credential rotation, actual role membership changes or deletion. Protected claims are not unlocked by age. Preserve unrelated handoffs/worktrees and private evidence. Use native bounded waits, not background promises.

## 8. Access and evidence custody
GitHub, GCP read access, Supabase read connector and 1Password are authenticated. Secret values were only consumed in memory or protected session state. Vault vibe_coding item qsp6qxxeufsawayy4qir32cuta is sandbox-only GUI login; its existing rotation incident belongs to another session. GCP sandbox database references were resolved in memory without printing values. A protected sandbox session and PostgreSQL test logs remain transient private evidence on edge-dev3; no production session exists. This pushed branch is the portable source of truth. Secrets sweep: no new exposed value or unvaulted secret. Documentation pass: no runtime behavior was changed; this handoff owns the findings without rewriting unrelated stale docs.

## 9. Open risks and self-audit
All delivery stages remain pending, not completed by local tests. GitHub availability, current heads, claims and CI are changeable and must be freshly verified. Production application access is unproven. No business question is waiting on Albert.

Self-audit: newcomer can resume from sections 1–3 and ordered gates in 6; all discovered dead ends and authority details are in 4–8; scope, failures, proof and limits are explicit; section 0 contains every owner decision (none). No gap requires chat context. No subagents, preview writes, production writes or secret values are hidden.
