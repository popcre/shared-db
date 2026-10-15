-- shared-db#4350 (claim #4355) live proof (read-only): Stage Catalog tables exist with
-- the seeded shape, RLS on and no policy on all six, no browser-role privilege on any,
-- the trigger function is security invoker with an empty search_path and all five
-- triggers call it, and the migration is in the ledger. Row totals that users edit
-- (durations, options, progress, dependencies) are checked as lower bounds or exact
-- seeded facts that edits do not change.
with t(name) as (values ('plm.stage_list'),('plm.stage'),('plm.stage_duration'),
  ('plm.stage_dependency'),('plm.licensor_stage_option'),('plm.prod_stage_progress'))
select (
  (select count(*) = 5 from plm.stage_list)
  and (select count(*) >= 24 from plm.stage)
  and (select count(*) >= 600 from plm.stage_duration)
  and (select count(*) >= 32 from plm.licensor_stage_option)
  and (select count(*) = 6 from t where (select relrowsecurity from pg_class where oid = t.name::regclass))
  and not exists (select 1 from pg_policy where polrelid in (select name::regclass from t))
  and not exists (select 1 from t cross join (values ('anon'),('authenticated')) r(role)
                  cross join (values ('select'),('insert'),('update'),('delete')) p(priv)
                  where has_table_privilege(r.role, t.name, p.priv))
  and (select count(*) = 1 from pg_proc p
        where p.oid = to_regprocedure('plm.stage_catalog_bump_version()')
          and not p.prosecdef and p.prorettype = 'trigger'::regtype
          and 'search_path=""' = any (p.proconfig))
  and (select count(*) = 5 from pg_trigger g
        where g.tgfoid = to_regprocedure('plm.stage_catalog_bump_version()') and not g.tgisinternal)
  and exists (select 1 from supabase_migrations.schema_migrations where version = '20261015193344')
) as passed;
