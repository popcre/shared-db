-- Live proof for #3174 (migration 20260917144950). Read-only.
-- Proves: the migration is in production's ledger; the inventory function carries the
-- five new sections; plm.sesame_submission_property_option exists with RLS and no
-- client read grant; the latest complete Peanuts capture yields 19 Tenovos-id rows.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260917144950')
  and position('''coca-cola-submissions''' in pg_get_functiondef('api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure)) > 0
  and position('''wwe-creative''' in pg_get_functiondef('api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure)) > 0
  and position('''peanuts-creative''' in pg_get_functiondef('api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure)) > 0
  and position('''sesame-creative''' in pg_get_functiondef('api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure)) > 0
  and position('''sesame-submissions''' in pg_get_functiondef('api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure)) > 0
  and coalesce((select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'plm' and c.relname = 'sesame_submission_property_option'), false)
  and not has_table_privilege('anon', 'plm.sesame_submission_property_option', 'select')
  and not has_table_privilege('authenticated', 'plm.sesame_submission_property_option', 'select')
  and (select count(*) from plm.peanuts_art_program a
       where a.source_value_id is not null
         and a.capture_id = (select c.id from plm.peanuts_capture c where c.status = 'complete'
                             order by c.source_captured_at desc, c.load_completed_at desc, c.id desc limit 1)) = 19
) as passed
