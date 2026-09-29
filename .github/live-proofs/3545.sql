-- Live proof for #3545 (migration 20260929031536). Read-only.
-- Proves: Classic is loaded and the inventory function exposes it under Submissions.
select (
  exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20260929031536'
  )
  and to_regclass('plm.wildbrain_submission_property_option') is not null
  and exists (
    select 1 from plm.wildbrain_submission_property_option
    where option_key = 'e608bfe3-a3e2-439a-899d-dc88a59e9b58'
      and exact_label = 'Strawberry Shortcake Classic'
  )
  and (select count(*) from plm.wildbrain_submission_property_option) = 1
  and position(
    'wildbrain-submissions',
    pg_get_functiondef('api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure)
  ) > 0
  and position(
    'plm.wildbrain_submission_property_option',
    pg_get_functiondef('api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure)
  ) > 0
  and not has_table_privilege('authenticated', 'plm.wildbrain_submission_property_option', 'select')
  and not has_table_privilege('anon', 'plm.wildbrain_submission_property_option', 'select')
) as passed
