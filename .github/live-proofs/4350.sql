-- shared-db#4350 (claim #4355) live proof (read-only): Stage Catalog tables exist with
-- the seeded counts, RLS on all six, no browser-role privilege, and the migration is in
-- the ledger.
select (
  (select count(*) = 5 from plm.stage_list)
  and (select count(*) = 24 from plm.stage)
  and (select count(*) >= 637 from plm.stage_duration)
  and (select count(*) = 16 from plm.licensor_stage_option where enabled)
  and (select count(*) = 6 from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'plm' and c.relrowsecurity
          and c.relname in ('stage_list','stage','stage_duration','stage_dependency',
                            'licensor_stage_option','prod_stage_progress'))
  and not has_table_privilege('authenticated', 'plm.stage_list', 'select')
  and not has_table_privilege('anon', 'plm.stage_list', 'select')
  and not has_table_privilege('authenticated', 'plm.prod_stage_progress', 'insert')
  and exists (select 1 from pg_trigger where tgname = 'stage_bump_version'
               and tgrelid = 'plm.stage'::regclass)
  and exists (select 1 from supabase_migrations.schema_migrations
               where version = '20261015193344')
) as passed;
