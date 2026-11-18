-- #6457: revoke superfluous anon/authenticated EXECUTE on 100 security-definer
-- functions dispositioned revoke-candidate by the #6416 SD-RPC matrix.
-- Part of the #2326 program (plan Step 6).
--
-- WHY
-- ---
-- The #6416 measurement (docs/verification/database-efficiency/
-- 20261116T050000Z-step6-6416-sd-rpc-matrix/sd-rpc-matrix.md) classified 201
-- SECURITY DEFINER non-trigger functions carrying anon/authenticated EXECUTE.
-- 107 had no application `.rpc()` caller in popdam3 / poppim-web / popcrm /
-- pop-mock / popdam / dflow_plm ("revoke-candidate"). This migration revokes
-- 100 of them. 7 are KEPT because SQL-internal caller analysis (2026-11-17,
-- preview catalog) found them reachable by API roles through RLS policies or
-- SECURITY INVOKER functions — revoking would break live application journeys:
--
--   app.current_profile_id          — called in 8+ RLS policies (app.profile,
--                                     app.notification, pim.saved_view, ...)
--   app.has_role(app.app_role)      — called in 200+ RLS policies across
--                                     core/crm/dam/plm/pim/public
--   app.has_any_role(app.app_role[]) — called in 150+ shared_read RLS policies
--   app.has_explicit_app_access     — called by app.require_licensing_manager_access
--                                     (SECURITY INVOKER, authenticated EXECUTE)
--   public.has_role(uuid, app_role) — called in archive/public RLS policies
--                                     (allowlisted in 20260729130000 for this reason)
--   public.assets_thumbnail_min_date — called by filter_effective_assets
--                                     (SECURITY INVOKER, authenticated EXECUTE)
--   public.refresh_style_group_primaries — called by run_full_reconcile_style_group_stats
--                                     (SECURITY INVOKER, PUBLIC EXECUTE)
--
-- The authenticated probe leg was OBTAINED 2026-11-17 (the prior blocker: GoTrue
-- user creation raised P0001 from public.handle_new_user()'s invitation check;
-- cleared by seeding a public.invitations row, then GoTrue admin create +
-- password grant). Per handoff trap 15, empty-args probes under-signal; the
-- dispositions are driven by the application .rpc() call-site search plus the
-- SQL-internal caller analysis above; the authenticated status codes corroborate.
--
-- WHY `from public, anon, authenticated` (same trap as #6415 / 20260729130000)
-- -----------------------------------------------------------------------
-- Most of these functions carry no explicit role grant: their ACL is the
-- function default (PUBLIC EXECUTE). Revoking only anon/authenticated is a
-- no-op — the PUBLIC pseudo-role is the real grant. postgres / service_role
-- grants are left untouched: SQL-level callers (other SECURITY DEFINER
-- functions running as their owner) are unaffected.
--
-- SCOPE
-- -----
-- An explicit list of 99 schema.name pairs (100 signatures — api.set_source_resolution
-- has two overloads). The loop is existence-guarded: a name absent from this
-- database is simply skipped (production-safe, 20260729130000 pattern). The
-- census predicate (prosecdef, non-trigger, API-role EXECUTE) narrows the match
-- to exactly the revoke-candidate surface.
--
-- ROLLBACK (named)
-- ----------------
-- Forward migration re-granting, for exactly the 100 signatures this PR lists
-- (captured in the PR body as the pre-change grant state):
--   grant execute on function <schema>.<name>(...) to public, anon, authenticated;
-- For names whose only pre-change grant was the function default, `to public`
-- restores the original state.
--
-- PREVIEW PROOF (issue #6457)
-- ---------------------------
-- 1. Authenticated-leg probe matrix recorded (status codes only) — done
--    2026-11-17, see issue comment.
-- 2. Post-revoke census: the 100 revoked names drop out of the prosecdef /
--    EXECUTE query on preview.
-- 3. No application journey breaks: each revoke names its search result
--    (no .rpc() caller); intended callers (76 + 7 kept) stay granted.

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
      'api.crm_admin_set_department_salespeople',
      'api.crm_admin_set_user_status',
      'api.crm_archive_contact',
      'api.crm_archive_customer',
      'api.crm_archive_opportunity',
      'api.crm_create_contact',
      'api.crm_create_opportunity',
      'api.crm_email_routing_segment_counts',
      'api.crm_merge_contacts',
      'api.crm_overview_counts',
      'api.crm_overview_email_counts',
      'api.crm_overview_email_volume',
      'api.crm_overview_pending_approvals',
      'api.crm_overview_pipeline_stages',
      'api.crm_overview_recent_meetings',
      'api.crm_overview_recent_unrouted',
      'api.crm_update_account',
      'api.db_data_admin_customer_detail',
      'api.db_data_admin_customer_list',
      'api.db_data_admin_licensor_property_list',
      'api.db_data_admin_merge_vendor',
      'api.db_data_admin_preview_vendor_merge',
      'api.db_data_admin_update_customer',
      'api.db_data_admin_update_vendor',
      'api.db_data_admin_vendor_detail',
      'api.db_data_admin_vendor_list',
      'api.pm_accept_activity_triage',
      'api.pm_add_product_comment',
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
      'api.set_source_resolution',
      'api.source_capture_inventory_exact',
      'api.taxonomy_baseline_pin_list',
      'api.taxonomy_sync_alert_list',
      'api.vendor_exclusion_list',
      'api.vendor_quarantine_list',
      'api.vendor_sync_run_list',
      'public.activate_popsg_property_decision_batch',
      'public.add_style_guide_manual_tag',
      'public.approve_licensor_alias',
      'public.bulk_assign_style_groups',
      'public.create_dam_order',
      'public.dam_resolve_customer',
      'public.dam_search_semantic_anchor',
      'public.dam_search_semantic_anchor_scoped',
      'public.dam_search_semantic_anchors',
      'public.expand_dam_search_queries',
      'public.get_dam_customer_facets',
      'public.get_dam_style_group_asset_count',
      'public.get_effective_filter_counts',
      'public.get_style_guide_deterministic_tag_batch',
      'public.import_dam_buy_sheet',
      'public.link_dam_order_line',
      'public.list_licensor_aliases',
      'public.promote_property_alias_batch',
      'public.propagate_group_tags_batch',
      'public.propose_popsg_property_resolution',
      'public.rebuild_dam_search_documents',
      'public.refresh_dam_search_asset_document',
      'public.refresh_style_group_counts',
      'public.refresh_style_group_counts_batch',
      'public.reject_style_guide_auto_tag',
      'public.remove_style_guide_manual_tag',
      'public.replace_style_guide_deterministic_tags',
      'public.replace_style_guide_folder_consensus_tags',
      'public.reset_bulk_operation_submission_lease',
      'public.resolve_coldlion_triage',
      'public.resolve_licensor_alias',
      'public.update_bulk_operations_batch',
      'public.update_dam_order',
      'public.update_dam_order_tracking',
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
      'api.crm_admin_set_department_salespeople',
      'api.crm_admin_set_user_status',
      'api.crm_archive_contact',
      'api.crm_archive_customer',
      'api.crm_archive_opportunity',
      'api.crm_create_contact',
      'api.crm_create_opportunity',
      'api.crm_email_routing_segment_counts',
      'api.crm_merge_contacts',
      'api.crm_overview_counts',
      'api.crm_overview_email_counts',
      'api.crm_overview_email_volume',
      'api.crm_overview_pending_approvals',
      'api.crm_overview_pipeline_stages',
      'api.crm_overview_recent_meetings',
      'api.crm_overview_recent_unrouted',
      'api.crm_update_account',
      'api.db_data_admin_customer_detail',
      'api.db_data_admin_customer_list',
      'api.db_data_admin_licensor_property_list',
      'api.db_data_admin_merge_vendor',
      'api.db_data_admin_preview_vendor_merge',
      'api.db_data_admin_update_customer',
      'api.db_data_admin_update_vendor',
      'api.db_data_admin_vendor_detail',
      'api.db_data_admin_vendor_list',
      'api.pm_accept_activity_triage',
      'api.pm_add_product_comment',
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
      'api.set_source_resolution',
      'api.source_capture_inventory_exact',
      'api.taxonomy_baseline_pin_list',
      'api.taxonomy_sync_alert_list',
      'api.vendor_exclusion_list',
      'api.vendor_quarantine_list',
      'api.vendor_sync_run_list',
      'public.activate_popsg_property_decision_batch',
      'public.add_style_guide_manual_tag',
      'public.approve_licensor_alias',
      'public.bulk_assign_style_groups',
      'public.create_dam_order',
      'public.dam_resolve_customer',
      'public.dam_search_semantic_anchor',
      'public.dam_search_semantic_anchor_scoped',
      'public.dam_search_semantic_anchors',
      'public.expand_dam_search_queries',
      'public.get_dam_customer_facets',
      'public.get_dam_style_group_asset_count',
      'public.get_effective_filter_counts',
      'public.get_style_guide_deterministic_tag_batch',
      'public.import_dam_buy_sheet',
      'public.link_dam_order_line',
      'public.list_licensor_aliases',
      'public.promote_property_alias_batch',
      'public.propagate_group_tags_batch',
      'public.propose_popsg_property_resolution',
      'public.rebuild_dam_search_documents',
      'public.refresh_dam_search_asset_document',
      'public.refresh_style_group_counts',
      'public.refresh_style_group_counts_batch',
      'public.reject_style_guide_auto_tag',
      'public.remove_style_guide_manual_tag',
      'public.replace_style_guide_deterministic_tags',
      'public.replace_style_guide_folder_consensus_tags',
      'public.reset_bulk_operation_submission_lease',
      'public.resolve_coldlion_triage',
      'public.resolve_licensor_alias',
      'public.update_bulk_operations_batch',
      'public.update_dam_order',
      'public.update_dam_order_tracking',
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

  -- Record the kept set explicitly (accepted boundary, RLS/invoker-reachable).
  raise notice 'kept (RLS/invoker-reachable, not in revoke set): app.current_profile_id, app.has_role, app.has_any_role, app.has_explicit_app_access, public.has_role, public.assets_thumbnail_min_date, public.refresh_style_group_primaries';
end
$$;

commit;
