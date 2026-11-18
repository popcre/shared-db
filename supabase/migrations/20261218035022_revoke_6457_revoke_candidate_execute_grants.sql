-- #6457: revoke superfluous anon/authenticated EXECUTE on security-definer
-- functions dispositioned revoke-candidate by the #6416 SD-RPC matrix.
-- Part of the #2326 program (plan Step 6).
--
-- WHY
-- ---
-- The #6416 measurement classified 201 SECURITY DEFINER non-trigger functions
-- carrying anon/authenticated EXECUTE. 107 had no application .rpc() caller
-- ("revoke-candidate"). This migration revokes 80 of them (80 signatures).
-- 27 are KEPT (26 unique names):
--
--   7 RLS/invoker-reachable (SQL-internal caller analysis 2026-11-17):
--     app.current_profile_id, app.has_role, app.has_any_role,
--     app.has_explicit_app_access, public.has_role, public.assets_thumbnail_min_date,
--     public.refresh_style_group_primaries
--
--   19 contract-test-pinned (supabase/tests assert authenticated/service_role
--   MUST retain EXECUTE — these are intended RPCs despite no .rpc() caller found):
--     api.set_source_resolution, api.crm_create_contact, api.crm_archive_contact,
--     api.crm_merge_contacts, api.crm_admin_set_department_salespeople,
--     api.db_data_admin_customer_detail, api.db_data_admin_customer_list,
--     api.db_data_admin_vendor_detail, api.pm_add_product_comment,
--     public.resolve_licensor_alias, public.import_dam_buy_sheet,
--     public.get_effective_filter_counts, public.expand_dam_search_queries,
--     public.activate_popsg_property_decision_batch, public.promote_property_alias_batch,
--     public.propose_popsg_property_resolution, public.refresh_style_group_counts_batch,
--     public.reset_bulk_operation_submission_lease, public.update_dam_order_tracking
--
-- The authenticated probe leg was OBTAINED 2026-11-17. Per handoff trap 15,
-- empty-args probes under-signal; dispositions are call-site-driven (.rpc()
-- search + SQL-internal caller analysis + contract-test scan); status codes
-- corroborate only.
--
-- WHY `from public, anon, authenticated` (same trap as #6415 / 20260729130000)
-- -----------------------------------------------------------------------
-- Most of these functions carry no explicit role grant: their ACL is the
-- function default (PUBLIC EXECUTE). Revoking only anon/authenticated is a
-- no-op — the PUBLIC pseudo-role is the real grant. postgres / service_role
-- grants are left untouched.
--
-- ROLLBACK (named)
-- ----------------
-- Forward migration re-granting for exactly the signatures this PR lists:
--   grant execute on function <schema>.<name>(...) to public, anon, authenticated;

begin;

do $$
declare
  r record;
  n integer := 0;
  remaining integer;
  leftover text;
begin
  for r in
    select format('%I.%I(%s)', n.nspname, p.proname,
                  pg_get_function_identity_arguments(p.oid)) as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname || '.' || p.proname in (
      'api.clickup_task_sync_run_list',
      'api.coldlion_licensor_property_run_list',
      'api.coldlion_parallel_observation_list',
      'api.coldlion_promotion_audit_list',
      'api.coldlion_promotion_quarantine_list',
      'api.crm_admin_access_history',
      'api.crm_admin_assign_departments',
      'api.crm_admin_department_assignments',
      'api.crm_admin_role_list',
      'api.crm_admin_set_app_access',
      'api.crm_admin_set_user_status',
      'api.crm_archive_customer',
      'api.crm_archive_opportunity',
      'api.crm_create_opportunity',
      'api.crm_email_routing_segment_counts',
      'api.crm_overview_counts',
      'api.crm_overview_email_counts',
      'api.crm_overview_email_volume',
      'api.crm_overview_pending_approvals',
      'api.crm_overview_pipeline_stages',
      'api.crm_overview_recent_meetings',
      'api.crm_overview_recent_unrouted',
      'api.crm_update_account',
      'api.db_data_admin_licensor_property_list',
      'api.db_data_admin_merge_vendor',
      'api.db_data_admin_preview_vendor_merge',
      'api.db_data_admin_update_customer',
      'api.db_data_admin_update_vendor',
      'api.db_data_admin_vendor_list',
      'api.pm_accept_activity_triage',
      'api.pm_begin_activity_triage',
      'api.pm_cancel_product_comment_reservation',
      'api.pm_complete_activity_triage',
      'api.pm_create_decision',
      'api.pm_create_dependency',
      'api.pm_create_reminder',
      'api.pm_dismiss_activity_triage',
      'api.pm_fail_activity_triage',
      'api.pm_get_activity_triage',
      'api.pm_list_active_jev_triage',
      'api.pm_list_reviewed_jev_triage',
      'api.pm_record_jev_suggestion_impression',
      'api.pm_recover_product_comment_handle',
      'api.pm_repair_comment_triage_queue',
      'api.pm_reserve_product_comment_operation',
      'api.pm_update_dependency_status',
      'api.pm_update_reminder_status',
      'api.pm_verify_jev_runtime_fence',
      'api.source_capture_inventory_exact',
      'api.taxonomy_baseline_pin_list',
      'api.taxonomy_sync_alert_list',
      'api.vendor_exclusion_list',
      'api.vendor_quarantine_list',
      'api.vendor_sync_run_list',
      'public.add_style_guide_manual_tag',
      'public.approve_licensor_alias',
      'public.bulk_assign_style_groups',
      'public.create_dam_order',
      'public.dam_resolve_customer',
      'public.dam_search_semantic_anchor',
      'public.dam_search_semantic_anchor_scoped',
      'public.dam_search_semantic_anchors',
      'public.get_dam_customer_facets',
      'public.get_dam_style_group_asset_count',
      'public.get_style_guide_deterministic_tag_batch',
      'public.link_dam_order_line',
      'public.list_licensor_aliases',
      'public.propagate_group_tags_batch',
      'public.rebuild_dam_search_documents',
      'public.refresh_dam_search_asset_document',
      'public.refresh_style_group_counts',
      'public.reject_style_guide_auto_tag',
      'public.remove_style_guide_manual_tag',
      'public.replace_style_guide_deterministic_tags',
      'public.replace_style_guide_folder_consensus_tags',
      'public.resolve_coldlion_triage',
      'public.update_bulk_operations_batch',
      'public.update_dam_order',
      'public.upsert_dam_order_customer_settings',
      'public.upsert_dam_order_sample_depth'
    )
      and p.prosecdef
      and p.prorettype not in ('trigger'::regtype, 'event_trigger'::regtype)
      and (has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or has_function_privilege('public', p.oid, 'EXECUTE'))
    order by 1
  loop
    execute format(
      'revoke execute on function %s from public, anon, authenticated', r.sig);
    n := n + 1;
  end loop;

  raise notice 'revoked EXECUTE on % function(s) in the #6457 revoke set', n;

  -- Assert: none of the revoke-set names still carries API-role EXECUTE.
  select count(*), string_agg(format('%I.%I', n.nspname, p.proname), ', ')
    into remaining, leftover
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname || '.' || p.proname in (
    'api.clickup_task_sync_run_list',
      'api.coldlion_licensor_property_run_list',
      'api.coldlion_parallel_observation_list',
      'api.coldlion_promotion_audit_list',
      'api.coldlion_promotion_quarantine_list',
      'api.crm_admin_access_history',
      'api.crm_admin_assign_departments',
      'api.crm_admin_department_assignments',
      'api.crm_admin_role_list',
      'api.crm_admin_set_app_access',
      'api.crm_admin_set_user_status',
      'api.crm_archive_customer',
      'api.crm_archive_opportunity',
      'api.crm_create_opportunity',
      'api.crm_email_routing_segment_counts',
      'api.crm_overview_counts',
      'api.crm_overview_email_counts',
      'api.crm_overview_email_volume',
      'api.crm_overview_pending_approvals',
      'api.crm_overview_pipeline_stages',
      'api.crm_overview_recent_meetings',
      'api.crm_overview_recent_unrouted',
      'api.crm_update_account',
      'api.db_data_admin_licensor_property_list',
      'api.db_data_admin_merge_vendor',
      'api.db_data_admin_preview_vendor_merge',
      'api.db_data_admin_update_customer',
      'api.db_data_admin_update_vendor',
      'api.db_data_admin_vendor_list',
      'api.pm_accept_activity_triage',
      'api.pm_begin_activity_triage',
      'api.pm_cancel_product_comment_reservation',
      'api.pm_complete_activity_triage',
      'api.pm_create_decision',
      'api.pm_create_dependency',
      'api.pm_create_reminder',
      'api.pm_dismiss_activity_triage',
      'api.pm_fail_activity_triage',
      'api.pm_get_activity_triage',
      'api.pm_list_active_jev_triage',
      'api.pm_list_reviewed_jev_triage',
      'api.pm_record_jev_suggestion_impression',
      'api.pm_recover_product_comment_handle',
      'api.pm_repair_comment_triage_queue',
      'api.pm_reserve_product_comment_operation',
      'api.pm_update_dependency_status',
      'api.pm_update_reminder_status',
      'api.pm_verify_jev_runtime_fence',
      'api.source_capture_inventory_exact',
      'api.taxonomy_baseline_pin_list',
      'api.taxonomy_sync_alert_list',
      'api.vendor_exclusion_list',
      'api.vendor_quarantine_list',
      'api.vendor_sync_run_list',
      'public.add_style_guide_manual_tag',
      'public.approve_licensor_alias',
      'public.bulk_assign_style_groups',
      'public.create_dam_order',
      'public.dam_resolve_customer',
      'public.dam_search_semantic_anchor',
      'public.dam_search_semantic_anchor_scoped',
      'public.dam_search_semantic_anchors',
      'public.get_dam_customer_facets',
      'public.get_dam_style_group_asset_count',
      'public.get_style_guide_deterministic_tag_batch',
      'public.link_dam_order_line',
      'public.list_licensor_aliases',
      'public.propagate_group_tags_batch',
      'public.rebuild_dam_search_documents',
      'public.refresh_dam_search_asset_document',
      'public.refresh_style_group_counts',
      'public.reject_style_guide_auto_tag',
      'public.remove_style_guide_manual_tag',
      'public.replace_style_guide_deterministic_tags',
      'public.replace_style_guide_folder_consensus_tags',
      'public.resolve_coldlion_triage',
      'public.update_bulk_operations_batch',
      'public.update_dam_order',
      'public.upsert_dam_order_customer_settings',
      'public.upsert_dam_order_sample_depth'
  )
    and p.prosecdef
    and p.prorettype not in ('trigger'::regtype, 'event_trigger'::regtype)
    and (has_function_privilege('anon', p.oid, 'EXECUTE')
      or has_function_privilege('authenticated', p.oid, 'EXECUTE')
      or has_function_privilege('public', p.oid, 'EXECUTE'));

  if remaining > 0 then
    raise exception 'revoke-set functions still exposed after revoke: %', leftover;
  end if;

  raise notice 'kept (RLS/invoker + contract-test-pinned, not in revoke set): 26 names / 27 signatures';
end
$$;

commit;
