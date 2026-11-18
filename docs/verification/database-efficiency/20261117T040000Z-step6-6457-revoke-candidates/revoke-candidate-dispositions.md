---
summary: "#6457 per-function disposition table: 80 revoke, 27 keep (RLS/invoker + contract-test-pinned); authenticated probe leg obtained 2026-11-17"
kind: proof
status: done
read-when: checking the #6457 revoke-candidate dispositions, the KEEP rationale (RLS/invoker + contract tests), or the authenticated probe leg evidence
---

# #6457 revoke-candidate disposition table — 2026-11-17 (corrected)

**Issue:** popcre/shared-db #6457
**Migration:** `20261218035022_revoke_6457_revoke_candidate_execute_grants.sql`
**Claim:** #6652 (closed with evidence)

## Summary

| disposition | count |
|---|---|
| revoke | **80** |
| keep | **27** |
| total | **107** |

## KEEP rationale — two classes

### Class 1: RLS/invoker-reachable (7 signatures)
Revoking breaks live application journeys (RLS policies or SECURITY INVOKER chains consumed by API roles).
Evidence: preview catalog pg_policies scan + pg_proc.prosrc scan + ACL check (2026-11-17).

### Class 2: Contract-test-pinned (20 signatures)
`supabase/tests` contract tests assert `authenticated` or `service_role` MUST retain EXECUTE.
These are intended RPCs despite no `.rpc()` caller found in the searched app repos.
Evidence: grep of `has_function_privilege` assertions in `supabase/tests/` (2026-11-17).

| function | contract test | assertion |
|---|---|---|
| `api.set_source_resolution` (both overloads) | api_set_source_resolution_contracts | authenticated MUST |
| `api.crm_create_contact` | crm_basic_crud_rpcs_contracts | authenticated=allowed |
| `api.crm_archive_contact` | crm_basic_crud_rpcs_contracts | authenticated=allowed |
| `api.crm_merge_contacts` | crm_basic_crud_rpcs_contracts | authenticated MUST |
| `api.crm_admin_set_department_salespeople` | crm_department_secondary_salesperson_contracts | authenticated MUST |
| `api.db_data_admin_customer_detail` | db_data_admin_contract_errata | authenticated MUST |
| `api.db_data_admin_customer_list` | db_data_admin_contract_errata | authenticated MUST |
| `api.db_data_admin_vendor_detail` | db_data_admin_contract_errata | authenticated MUST |
| `api.pm_add_product_comment` | jev_activity_triage_contract_a | authenticated MUST |
| `public.resolve_licensor_alias` | core_licensor_alias_contracts F2 | authenticated MUST |
| `public.import_dam_buy_sheet` | dam_order_buy_sheet_import_contracts | authenticated MUST |
| `public.get_effective_filter_counts` | popdam_effective_asset_filter_contracts | authenticated MUST |
| `public.expand_dam_search_queries` | popdam_compound_word_variants_contracts | authenticated MUST |
| `public.activate_popsg_property_decision_batch` | popsg_property_resolution_contracts E2 | service_role MUST |
| `public.promote_property_alias_batch` | popsg_property_resolution_contracts E3 | authenticated MUST |
| `public.propose_popsg_property_resolution` | popsg_property_resolution_contracts E1 | authenticated MUST |
| `public.refresh_style_group_counts_batch` | style_group_counts_change_predicate_contracts | roles MUST (issue #2214) |
| `public.reset_bulk_operation_submission_lease` | popdam_submission_lease_reset_widen_contracts | authenticated MUST |
| `public.update_dam_order_tracking` | dam_order_sheets_integration | DAM workflow RPC |
| `public.assets_thumbnail_min_date` | popdam_effective_asset_filter_contracts | authenticated MUST (also invoker) |

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
| `api.crm_admin_set_department_salespeople(uuid[],uuid[])` | KEEP | anon:404 auth:404 | CONTRACT: crm_department_secondary_salesperson_contracts asserts authenticated MUST have EXECUTE |
| `api.crm_admin_set_user_status(uuid,text)` | revoke | anon:404 auth:404 | no .rpc() caller; called only by api.dflow_admin_set_user_status (SD) |
| `api.crm_archive_contact(uuid)` | KEEP | anon:404 auth:404 | CONTRACT: crm_basic_crud_rpcs_contracts asserts "public/anon=denied, authenticated=allowed" for CRUD RPCs |
| `api.crm_archive_customer(uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_archive_opportunity(uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_create_contact(text,text,text,text,uuid,uuid,text)` | KEEP | anon:404 auth:404 | CONTRACT: crm_basic_crud_rpcs_contracts asserts "public/anon=denied, authenticated=allowed" for CRUD RPCs |
| `api.crm_create_opportunity(text,uuid,uuid,uuid,text,numeric,date)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.crm_email_routing_segment_counts()` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_merge_contacts(uuid,uuid)` | KEEP | anon:404 auth:404 | CONTRACT: crm_basic_crud_rpcs_contracts asserts authenticated MUST have EXECUTE |
| `api.crm_overview_counts()` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_email_counts()` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_email_volume(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_pending_approvals(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_pipeline_stages()` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_recent_meetings(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_overview_recent_unrouted(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.crm_update_account(uuid,text,text,text,text,text,text)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_customer_detail(uuid)` | KEEP | anon:404 auth:404 | CONTRACT: db_data_admin_contract_errata asserts authenticated MUST have EXECUTE |
| `api.db_data_admin_customer_list(text,text,text,text,boolean,text,text,text,integer,uuid)` | KEEP | anon:404 auth:404 | CONTRACT: db_data_admin_contract_errata asserts authenticated MUST have EXECUTE |
| `api.db_data_admin_licensor_property_list(text,boolean,text,integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_merge_vendor(uuid,uuid,text,uuid,text,jsonb)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_preview_vendor_merge(uuid,uuid)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.db_data_admin_update_customer(uuid,timestamp with time zone,uuid,text,text,text,text,text,uuid[])` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.db_data_admin_update_vendor(uuid,timestamp with time zone,uuid,text,text,text,text,text)` | revoke | anon:404 auth:404 | no .rpc() caller; refs current_profile_id internally (SD) |
| `api.db_data_admin_vendor_detail(uuid)` | KEEP | anon:404 auth:404 | CONTRACT: db_data_admin_contract_errata asserts authenticated MUST have EXECUTE |
| `api.db_data_admin_vendor_list(text,text,text,text,boolean,text,text,text,integer)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.pm_accept_activity_triage(uuid,text,text,text,date)` | revoke | anon:404 auth:404 | no .rpc() caller; refs pm_create_* internally (SD) |
| `api.pm_add_product_comment(uuid,text,uuid)` | KEEP | anon:404 auth:404 | CONTRACT: jev_activity_triage_contract_a asserts authenticated MUST have EXECUTE |
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
| `api.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamp with time zone,uuid,uuid)` | KEEP | anon:404 auth:404 | CONTRACT: api_set_source_resolution_contracts asserts authenticated MUST have EXECUTE |
| `api.set_source_resolution(text,text,text,text,uuid,uuid,uuid,uuid,text,timestamp with time zone)` | KEEP | anon:404 auth:404 | CONTRACT: api_set_source_resolution_contracts asserts authenticated MUST have EXECUTE (same name) |
| `api.source_capture_inventory_exact(text)` | revoke | anon:404 auth:404 | no .rpc() caller; no SQL-internal caller found |
| `api.taxonomy_baseline_pin_list(text,boolean)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.taxonomy_sync_alert_list(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.vendor_exclusion_list()` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.vendor_quarantine_list()` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `api.vendor_sync_run_list(integer)` | revoke | anon:404 auth:404 | no .rpc() caller; only SD internal callers |
| `app.current_profile_id()` | KEEP | anon:404 auth:404 | RLS: 8+ policies (app.profile, app.notification, pim.saved_view, pim.ai_activity_triage) |
| `app.has_any_role(app.app_role[])` | KEEP | anon:404 auth:404 | RLS: 150+ shared_read policies; also invoker caller require_db_data_admin_product_depth_access |
| `app.has_explicit_app_access(app.app_name)` | KEEP | anon:404 auth:404 | INVOKER: require_licensing_manager_access (authenticated EXECUTE); 4 api views |
| `app.has_role(app.app_role)` | KEEP | anon:404 auth:404 | RLS: 200+ policies across core/crm/dam/plm/pim/public; invoker callers require_*_access |
| `activate_popsg_property_decision_batch(text,text,integer)` | KEEP | anon:n/a auth:n/a | CONTRACT: popsg_property_resolution_contracts E2 asserts service_role MUST have EXECUTE |
| `add_style_guide_manual_tag(uuid,text,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `approve_licensor_alias(text,text,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |
| `assets_thumbnail_min_date()` | KEEP | anon:n/a auth:n/a | INVOKER: filter_effective_assets (authenticated EXECUTE); CONTRACT: popdam_effective_asset_filter asserts authenticated MUST |
| `bulk_assign_style_groups(jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `create_dam_order(jsonb,jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `dam_resolve_customer(text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `dam_search_semantic_anchor(extensions.vector,text[])` | revoke | anon:n/a auth:n/a | no .rpc() caller; called only by dam_search_semantic_anchor_named/_scoped (SD) |
| `dam_search_semantic_anchor_scoped(extensions.vector,text[],uuid[])` | revoke | anon:n/a auth:n/a | no .rpc() caller; refs dam_search_semantic_anchor internally (SD); test only checks anon-denied |
| `dam_search_semantic_anchors(extensions.vector,extensions.vector,text[])` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `expand_dam_search_queries(text)` | KEEP | anon:n/a auth:n/a | CONTRACT: popdam_compound_word_variants asserts authenticated MUST have EXECUTE |
| `get_dam_customer_facets()` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found; auth probe 401->200 |
| `get_dam_style_group_asset_count(jsonb,timestamp with time zone,uuid[],text[])` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `get_effective_filter_counts(jsonb)` | KEEP | anon:n/a auth:n/a | CONTRACT: popdam_effective_asset_filter asserts authenticated MUST have EXECUTE |
| `get_style_guide_deterministic_tag_batch(uuid,integer,boolean)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `has_role(uuid,app_role)` | KEEP | anon:n/a auth:n/a | RLS: archive.erp_items_* + 50+ public.* admin policies; allowlisted in 20260729130000 |
| `import_dam_buy_sheet(uuid,text,text,jsonb,jsonb,jsonb,boolean)` | KEEP | anon:n/a auth:n/a | CONTRACT: dam_order_buy_sheet_import asserts authenticated MUST have EXECUTE |
| `link_dam_order_line(uuid,uuid,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `list_licensor_aliases()` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found; auth probe 401->200 |
| `promote_property_alias_batch(uuid,text,text,boolean,text,text,text)` | KEEP | anon:n/a auth:n/a | CONTRACT: popsg_property_resolution_contracts E3 asserts authenticated MUST have EXECUTE |
| `propagate_group_tags_batch(uuid,integer)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found; auth probe 401->200 |
| `propose_popsg_property_resolution(uuid,text,text,uuid,integer,text,text,text,text)` | KEEP | anon:n/a auth:n/a | CONTRACT: popsg_property_resolution_contracts E1 asserts authenticated MUST have EXECUTE |
| `rebuild_dam_search_documents()` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found; auth probe 401->400 |
| `refresh_dam_search_asset_document(uuid)` | revoke | anon:n/a auth:n/a | no .rpc() caller; called only by trigger/SD functions |
| `refresh_style_group_counts()` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found; auth probe 401->500 |
| `refresh_style_group_counts_batch(uuid[])` | KEEP | anon:n/a auth:n/a | CONTRACT: style_group_counts_change_predicate asserts roles MUST keep EXECUTE (issue #2214) |
| `refresh_style_group_primaries(uuid[])` | KEEP | anon:n/a auth:n/a | INVOKER: run_full_reconcile_style_group_stats (PUBLIC EXECUTE) |
| `reject_style_guide_auto_tag(uuid,uuid)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |
| `remove_style_guide_manual_tag(uuid,uuid)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `replace_style_guide_deterministic_tags(uuid,jsonb,text,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `replace_style_guide_folder_consensus_tags(uuid,jsonb,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `reset_bulk_operation_submission_lease(text,bigint,text,text,text,integer,jsonb)` | KEEP | anon:n/a auth:n/a | CONTRACT: popdam_submission_lease_reset_widen asserts authenticated MUST have EXECUTE |
| `resolve_coldlion_triage(uuid,text,uuid)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `resolve_licensor_alias(text)` | KEEP | anon:n/a auth:n/a | CONTRACT: core_licensor_alias_contracts F2 asserts authenticated MUST have EXECUTE |
| `update_bulk_operations_batch(jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `update_dam_order(uuid,jsonb,jsonb)` | revoke | anon:n/a auth:n/a | no .rpc() caller; no SQL-internal caller found |
| `update_dam_order_tracking(uuid,jsonb)` | KEEP | anon:n/a auth:n/a | CONTRACT: dam_order_sheets_integration; DAM order workflow RPC |
| `upsert_dam_order_customer_settings(text,text)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |
| `upsert_dam_order_sample_depth(text,text,numeric)` | revoke | anon:n/a auth:n/a | no .rpc() caller; only SD internal callers (refs has_role) |

## Method

1. Application `.rpc()` call-site search (from #6416): popdam3/poppim-web/popcrm/pop-mock/popdam/dflow_plm.
2. SQL-internal caller analysis (2026-11-17): pg_policies, pg_proc.prosrc, pg_views, ACLs.
3. Contract-test scan (2026-11-17): grep `has_function_privilege` in `supabase/tests/` for each revoke target.
4. Authenticated probe leg (2026-11-17): 180 functions, empty args, status codes.
5. Disposition: revoke = no .rpc() caller AND no RLS/invoker chain AND no contract-test pin.
   keep = any of those three evidence classes found.

Posted by MiMo chat ses_ffe5e136 on edge-dev
