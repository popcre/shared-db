-- #4268: catalog-only proof; application dates and caller behavior are proved on PopDAM #277.
select coalesce((
  select p.prosecdef and p.provolatile = 's'
    and p.proconfig = array['search_path=pg_catalog']
    and has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and not has_function_privilege('anon', p.oid, 'EXECUTE')
    and position('1500' in pg_get_functiondef(p.oid)) > 0
    and position('America/New_York' in pg_get_functiondef(p.oid)) > 0
    and position('count(distinct h.created_time) = 1' in pg_get_functiondef(p.oid)) > 0
  from pg_catalog.pg_proc p
  where p.oid = to_regprocedure('public.get_dam_order_sales_order_dates(uuid[])')
), false)
  and not has_table_privilege('authenticated', 'coldlion.order_history_line', 'SELECT')
  and not has_table_privilege('anon', 'coldlion.order_history_line', 'SELECT')
  and exists (select 1 from supabase_migrations.schema_migrations where version = '20261013211042')
  as passed;
