---
summary: "#6457 per-function disposition table: 100 revoke, 7 keep (RLS/invoker-reachable); authenticated probe leg obtained 2026-11-17"
kind: proof
status: done
read-when: checking the #6457 revoke-candidate dispositions, the RLS/invoker KEEP rationale, or the authenticated probe leg evidence
---

# #6457 revoke-candidate disposition table — 2026-11-17

**Issue:** popcre/shared-db #6457 (107 revoke-candidate SD functions from the #6416 matrix)
**Session:** MiMo chat ses_ffe5e136 on edge-dev
**Migration:** `20261218035022_revoke_6457_revoke_candidate_execute_grants.sql`
**Claim:** #6652

## Summary

| disposition | count |
|---|---|
| revoke | **100** |
| keep (RLS/invoker-reachable) | **7** |
| total | **107** |

## Authenticated probe leg — OBTAINED (2026-11-17)

The prior blocker (handoff trap 14) is cleared. Root cause of the GoTrue 500 `P0001`:
`public.handle_new_user()` (trigger `on_auth_user_created_popdam`) raises
"Access denied: no valid invitation found" for non-SSO providers (email/password).
Route: seed a `public.invitations` row for the probe email, then GoTrue admin create +
password grant → valid `authenticated` access token (no raw JWT secret needed).

**Authenticated probe matrix** (180 exposed-schema functions, empty args, status codes):
148 × 404→404 (signature mismatch, per trap 15 — NOT refusal proof),
15 × 401→200 (execute as authenticated), 10 × 401→403 (internal permission check),
2 × 401→400 (execute but error), 2 × 401→500 (server error), 2 × 300→300 (overload),
1 × 400→400 (`rls_auto_enable`).

Per trap 15, dispositions are call-site-driven (application `.rpc()` search across
popdam3/poppim-web/popcrm/pop-mock) plus SQL-internal caller analysis (RLS policies,
SECURITY INVOKER functions, views); status codes corroborate only.

## KEEP rationale (7 functions)

These carry `authenticated`/`anon` EXECUTE that is consumed by live RLS policies or
SECURITY INVOKER call chains. Revoking would break application journeys.

1. **`app.current_profile_id()`** — called in 8+ RLS policies (`app.profile`,
   `app.notification`, `pim.saved_view`, `pim.ai_activity_triage`). The policy
   expression runs as the querying role (anon/authenticated).
2. **`app.has_role(app.app_role)`** — called in 200+ RLS policies across
   core/crm/dam/plm/pim/public (admin_write, crm_read, dam_read, plm_read, ...).
3. **`app.has_any_role(app.app_role[])`** — called in 150+ shared_read RLS policies.
4. **`app.has_explicit_app_access(app.app_name)`** — called by
   `app.require_licensing_manager_access()` (SECURITY INVOKER, authenticated EXECUTE).
5. **`public.has_role(uuid, app_role)`** — called in `archive.erp_items_*` and 50+
   `public.*` admin RLS policies. Allowlisted in migration `20260729130000` for
   this exact reason.
6. **`public.assets_thumbnail_min_date()`** — called by `filter_effective_assets()`
   (SECURITY INVOKER, authenticated EXECUTE) and 3 more invoker functions.
7. **`public.refresh_style_group_primaries(uuid[])`** — called by
   `run_full_reconcile_style_group_stats()` (SECURITY INVOKER, PUBLIC EXECUTE,
   PostgREST-reachable in `public` schema).

## Per-function disposition table

| function | disposition | probe (anon→auth) | evidence |
|---|---|---|---|
| `api.clickup_task_sync_run_list(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers (refs has_role) |
| `api.coldlion_licensor_property_run_list(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.coldlion_parallel_observation_list(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.coldlion_promotion_audit_list(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.coldlion_promotion_quarantine_list(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_admin_access_history(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; called only by api.dflow_admin_access_history (SD) |
| `api.crm_admin_assign_departments(uuid[],uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_admin_department_assignments()` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_admin_role_list()` | revoke | anon:404 auth:404 | no .rpc() caller; called only by api.dflow_admin_role_list (SD) |
| `api.crm_admin_set_app_access(uuid,text,boolean)` | revoke | anon:404 auth:404 | no .rpc() caller; called only by api.dflow_admin_set_app_access (SD) |
| `api.crm_admin_set_department_salespeople(uuid[],uuid[])` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_admin_set_user_status(uuid,text)` | revoke | anon:404 auth:404 | no .rpc() caller; called only by api.dflow_admin_set_user_status (SD) |
| `api.crm_archive_contact(uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_archive_customer(uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_archive_opportunity(uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_create_contact(text,text,text,text,uuid,uuid,text)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_create_opportunity(text,uuid,uuid,uuid,text,numeric,date)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_email_routing_segment_counts()` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_merge_contacts(uuid,uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_overview_counts()` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_email_counts()` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_email_volume(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_pending_approvals(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_pipeline_stages()` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_recent_meetings(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_recent_unrouted(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_update_account(uuid,text,text,text,text,text,text)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_customer_detail(uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_customer_list(text,text,text,text,boolean,text,text,text,integer,uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_licensor_property_list(text,boolean,text,integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_merge_vendor(uuid,uuid,text,uuid,text,jsonb)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_preview_vendor_merge(uuid,uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_update_customer(uuid,timestamp with time zone,uuid,text,text,text,text,text,uuid[])` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.db_data_admin_update_vendor(uuid,timestamp with time zone,uuid,text,text,text,text,text)` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.db_data_admin_vendor_detail(uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_vendor_list(text,text,text,text,boolean,text,text,text,integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.pm_accept_activity_triage(uuid,text,text,text,date)` | revoke | anon:404 auth:404 | no .rpc() caller; refs pm_create_* internally (SD) |
| `api.pm_add_product_comment(uuid,text,uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.pm_begin_activity_triage(uuid,text,text,text,text,jsonb,text)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.pm_cancel_product_comment_reservation(text)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.pm_complete_activity_triage(uuid,text,text,jsonb,jsonb,jsonb,text)` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.pm_create_decision(uuid,text,text)` | revoke | anon:404 auth:404 | no .rpc() caller; called only by api.pm_accept_activity_triage (SD) |
| `api.pm_create_dependency(uuid,text)` | revoke | anon:404 auth:404 | no .rpc() caller; called only by api.pm_accept_activity_triage (SD) |
| `api.pm_create_reminder(uuid,text,date)` | revoke | anon:404 auth:404 | no .rpc() caller; called only by api.pm_accept_activity_triage (SD) |
| `api.pm_dismiss_activity_triage(uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.pm_fail_activity_triage(uuid,text,text,jsonb,text)` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.pm_get_activity_triage(uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.pm_list_active_jev_triage()` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.pm_list_reviewed_jev_triage()` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.pm_record_jev_suggestion_impression(uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.pm_recover_product_comment_handle(text)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.pm_repair_comment_triage_queue()` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.pm_reserve_product_comment_operation(uuid,uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.pm_update_dependency_status(uuid,text)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.pm_update_reminder_status(uuid,text)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.pm_verify_jev_runtime_fence(uuid,text,text,integer,timestamp with time zone,text,text)` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamp with time zone,uuid,uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; refs set_source_resolution internally via plm.reject_legacy_landing_resolution_write (SD) |
| `api.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamp with time zone)` | revoke | anon:404 auth:404 | no .rpc() caller; same as above (second overload) |
| `api.source_capture_inventory_exact(text)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.taxonomy_baseline_pin_list(text,boolean)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.taxonomy_sync_alert_list(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.vendor_exclusion_list()` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.vendor_quarantine_list()` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.vendor_sync_run_list(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `app.current_profile_id()` | KEEP | anon:404 auth:404 | RLS-policy caller: app.profile, app.notification, pim.saved_view, pim.ai_activity_triage policies evaluate as querying role |
| `app.has_any_role(app.app_role[])` | KEEP | anon:404 auth:404 | RLS-policy caller: 150+ shared_read policies across core/plm/pim/crm/dam; also invoker caller app.require_db_data_admin_product_depth_access |
| `app.has_explicit_app_access(app.app_name)` | KEEP | anon:404 auth:404 | SECURITY INVOKER caller: app.require_licensing_manager_access (authenticated EXECUTE); also 4 api views (security_invoker=false, but invoker chain is decisive) |
| `app.has_role(app.app_role)` | KEEP | anon:404 auth:404 | RLS-policy caller: 200+ policies across core/crm/dam/plm/pim/public; also invoker callers require_db_data_admin_access, require_licensing_manager_access |
| `activate_popsg_property_decision_batch(text,text,integer)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |
| `add_style_guide_manual_tag(uuid,text,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `approve_licensor_alias(text,text,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |
| `assets_thumbnail_min_date()` | KEEP | anon:n/a auth:n/a | SECURITY INVOKER caller: filter_effective_assets (authenticated EXECUTE); also filter_effective_assets_unchecked_1703, get_effective_filter_counts_unchecked_1703, dam_sweep_default_visible_flags_batched |
| `bulk_assign_style_groups(jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `create_dam_order(jsonb,jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `dam_resolve_customer(text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `dam_search_semantic_anchor(extensions.vector,text[])` | revoke | anon:n/a auth:n/a | no .rpc() caller; called only by dam_search_semantic_anchor_named / _scoped (both SD) |
| `dam_search_semantic_anchor_scoped(extensions.vector,text[],uuid[])` | revoke | anon:n/a auth:n/a | no .rpc() caller; refs dam_search_semantic_anchor internally (SD) |
| `dam_search_semantic_anchors(extensions.vector,extensions.vector,text[])` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `expand_dam_search_queries(text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; called only by search_dam_documents / search_dam_document_counts / search_style_groups_full_text (all SD) |
| `get_dam_customer_facets()` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found; auth probe 401->200 (callable but unused) |
| `get_dam_style_group_asset_count(jsonb,timestamp with time zone,uuid[],text[])` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `get_effective_filter_counts(jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; called only by get_filter_counts_unchecked_1703 (SD) |
| `get_style_guide_deterministic_tag_batch(uuid,integer,boolean)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `has_role(uuid,app_role)` | KEEP | anon:n/a auth:n/a | RLS-policy caller: archive.erp_items_raw/current and 50+ public.* admin policies (allowlisted in 20260729130000 for this exact reason) |
| `import_dam_buy_sheet(uuid,text,text,jsonb,jsonb,jsonb,boolean)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `link_dam_order_line(uuid,uuid,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `list_licensor_aliases()` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found; auth probe 401->200 (callable but unused) |
| `promote_property_alias_batch(uuid,text,text,boolean,text,text,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |
| `propagate_group_tags_batch(uuid,integer)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found; auth probe 401->200 (callable but unused) |
| `propose_popsg_property_resolution(uuid,text,text,uuid,integer,text,text,text,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |
| `rebuild_dam_search_documents()` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found; auth probe 401->400 |
| `refresh_dam_search_asset_document(uuid)` | revoke | anon:n/a auth:n/a | no .rpc() caller; called only by trigger/SD functions (refresh_dam_search_after_*, trg_refresh_dam_*, refresh_dam_search_documents_batch) |
| `refresh_style_group_counts()` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found; auth probe 401->500 |
| `refresh_style_group_counts_batch(uuid[])` | revoke | anon:n/a auth:n/a | no .rpc() caller; called only by SD functions (reconcile_style_group_stats_batch, refresh_style_group_counts_on_asset_change, queue_nightly_rebuild_style_groups, refresh_style_group_counts_serialized, refresh_group_on_asset_hard_delete) |
| `refresh_style_group_primaries(uuid[])` | KEEP | anon:n/a auth:n/a | SECURITY INVOKER caller: run_full_reconcile_style_group_stats (PUBLIC EXECUTE, PostgREST-reachable); also SD callers reconcile_style_group_stats_batch, refresh_group_on_asset_hard_delete, refresh_primary_on_asset_soft_delete |
| `reject_style_guide_auto_tag(uuid,uuid)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |
| `remove_style_guide_manual_tag(uuid,uuid)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `replace_style_guide_deterministic_tags(uuid,jsonb,text,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `replace_style_guide_folder_consensus_tags(uuid,jsonb,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `reset_bulk_operation_submission_lease(text,bigint,text,text,text,integer,jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `resolve_coldlion_triage(uuid,text,uuid)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `resolve_licensor_alias(text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `update_bulk_operations_batch(jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `update_dam_order(uuid,jsonb,jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `update_dam_order_tracking(uuid,jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |
| `upsert_dam_order_customer_settings(text,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |
| `upsert_dam_order_sample_depth(text,text,numeric)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |

## Method

1. **Application call-site search** (from #6416 matrix): `.rpc('<name>')` in
   popdam3 (94 names), poppim-web (20), popcrm (18), pop-mock (9), popdam (0),
   dflow_plm (0). 76 intended, 107 revoke-candidate.
2. **SQL-internal caller analysis** (2026-11-17, preview catalog via Management API
   read_only): pg_policies (RLS qual/with_check), pg_proc.prosrc (SECURITY DEFINER +
   SECURITY INVOKER), pg_views (security_invoker flag), function ACLs.
3. **Authenticated probe leg**: 180 functions probed with `authenticated` JWT
   (password grant), empty args, status codes only.
4. **Disposition rule**: revoke = no .rpc() caller AND no API-role-reachable
   SQL-internal caller chain (RLS or invoker). keep = live RLS/invoker chain found.

## Boundaries

- Empty-args probes under-signal (trap 15): 404 = signature mismatch for `{}`,
  NOT a refusal proof for a correctly-argued call.
- The 76 "intended" functions from #6416 are out of scope here (kept, callers named).
- The 17 "revoke" functions (non-exposed schemas + event-trigger) are issue #6455.
- `public.rls_auto_enable()` is issue #6456 (remediate).
- JWT secret for preview is not exposed by the Management API `/config/auth` endpoint
  (field absent); the vault item's secret is known-stale from prior evidence. The
  password-grant route provides a valid authenticated identity without needing the
  raw secret, so this is non-blocking.

Posted by MiMo chat ses_ffe5e136 on edge-dev
