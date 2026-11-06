-- #4474 live proof (read-only): after the 20261106163507 apply, anon and
-- authenticated must hold no EXECUTE on the two plm SECURITY DEFINER
-- functions, service_role must still hold both, the migration must be on the
-- ledger, and the public zero-arg wrapper must keep its authenticated access
-- (deliberate allowlist entry of 20260729120000 — untouched by this change).
select
  not has_function_privilege('anon', 'plm.apply_style_tracker_designer_resolutions()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'plm.apply_style_tracker_designer_resolutions()', 'EXECUTE')
  and not has_function_privilege('anon', 'plm.refresh_style_tracker_item_bridge()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'plm.refresh_style_tracker_item_bridge()', 'EXECUTE')
  and has_function_privilege('service_role', 'plm.apply_style_tracker_designer_resolutions()', 'EXECUTE')
  and has_function_privilege('service_role', 'plm.refresh_style_tracker_item_bridge()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.refresh_style_tracker_item_bridge()', 'EXECUTE')
  and exists(select 1 from supabase_migrations.schema_migrations where version = '20261106163507')
  as passed;
