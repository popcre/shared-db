-- shared-db#4350 (claim #4355) live proof (read-only): the Stage Catalog tables exist
-- with the seeded shape, RLS on and no policy on all six, no browser-role privilege on
-- any table or on the trigger function, the function is security invoker with an empty
-- search_path and all five triggers call it, SKU progress is unique with empty SKU
-- refused, and the migration is in the ledger. Facts users may later edit (lists,
-- stages, durations, options, flags) are lower bounds; facts no edit path changes
-- before the API ships (dependencies and progress start empty) are checked from the
-- migration's own seed assertion through the ledger row instead of exact counts.
with t(name) as (values ('plm.stage_list'),('plm.stage'),('plm.stage_duration'),
  ('plm.stage_dependency'),('plm.licensor_stage_option'),('plm.prod_stage_progress'))
select (
  (select count(*) >= 5 from plm.stage_list)
  and (select count(*) >= 24 from plm.stage)
  and (select count(*) >= 600 from plm.stage_duration)
  and (select count(*) >= 60 from plm.stage_duration where scope_kind = 'licensor')
  and (select count(*) >= 32 from plm.licensor_stage_option)
  and (select count(*) >= 1 from plm.licensor_stage_option where enabled)
  and (select count(*) >= 1 from plm.stage where shown_on_tracker)
  and exists (select 1 from plm.stage_list where key = 'sampling' and maintainers @> '{36,41}'::integer[])
  and (select count(*) = 6 from t where (select relrowsecurity from pg_class where oid = t.name::regclass))
  and not exists (select 1 from pg_policy where polrelid in (select name::regclass from t))
  and not exists (select 1 from t cross join (values ('anon'),('authenticated')) r(role)
                  cross join (values ('select'),('insert'),('update'),('delete')) p(priv)
                  where has_table_privilege(r.role, t.name, p.priv))
  and (select count(*) = 1 from pg_proc p
        where p.oid = to_regprocedure('plm.stage_catalog_bump_version()')
          and not p.prosecdef and p.prorettype = 'trigger'::regtype
          and 'search_path=""' = any (p.proconfig))
  and not has_function_privilege('anon', 'plm.stage_catalog_bump_version()', 'execute')
  and not has_function_privilege('authenticated', 'plm.stage_catalog_bump_version()', 'execute')
  and (select count(*) = 5 from pg_trigger g
        where g.tgfoid = to_regprocedure('plm.stage_catalog_bump_version()') and not g.tgisinternal)
  and exists (select 1 from pg_index i where i.indexrelid = 'plm.prod_stage_progress_order_sku_stage_key'::regclass
               and i.indisunique)
  and exists (select 1 from pg_constraint c where c.conrelid = 'plm.prod_stage_progress'::regclass
               and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%sku%')
  and exists (select 1 from supabase_migrations.schema_migrations where version = '20261015193344')
) as passed;
