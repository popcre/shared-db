-- #3545 read-only production proof (migration 20260930202719).
-- Catalog only: the Management API's supabase_read_only_user cannot read licensed
-- plm rows or pass the Licensing gate of the inventory RPC, so the row-level page
-- proof (Classic listed, root/Classic mapped, 2003/Berry/Bitty omitted) is run
-- separately through the RPC as an authenticated Licensing principal and recorded
-- on issue #3545 (read-only transaction, set local role authenticated, a
-- production Licensing profile's JWT subject). The two position() checks below
-- are catalog corroboration only; that RPC run is the row-level evidence.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260930202719')
  and to_regclass('plm.wildbrain_submission_property_option') is not null
  and exists (
    select 1 from pg_constraint
    where conrelid = to_regclass('plm.wildbrain_submission_property_option')
      and conname = 'wildbrain_submission_property_option_owner_scope_chk'
      and pg_get_constraintdef(oid) like '%e608bfe3-a3e2-439a-899d-dc88a59e9b58%')
  and (select relrowsecurity from pg_class
       where oid = to_regclass('plm.wildbrain_submission_property_option'))
  and exists (
    select 1 from pg_policies
    where schemaname = 'plm' and tablename = 'wildbrain_submission_property_option'
      and policyname = 'wildbrain_submission_property_option_plm_read')
  and exists (
    select 1 from pg_policies
    where schemaname = 'plm' and tablename = 'wildbrain_submission_property_option'
      and policyname = 'wildbrain_submission_property_option_service_read')
  and not has_table_privilege('anon', 'plm.wildbrain_submission_property_option', 'select')
  and exists (
    select 1 from pg_constraint
    where conname = 'dcp_opa_property_resolution_creative_state_ck'
      and conrelid = to_regclass('plm.dcp_opa_property_resolution')
      and pg_get_constraintdef(oid) like '%excluded%')
  and position('wildbrain-submissions' in pg_get_functiondef(
    'api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure)) > 0
  and position('in (select x.identity_key from excluded_identity x)' in pg_get_functiondef(
    'api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure)) > 0
) as passed;
