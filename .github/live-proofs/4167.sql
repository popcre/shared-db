select (
  (select count(*) = 1
   from pg_proc p
   where p.oid = to_regprocedure('public.apply_erp_item_updates(jsonb)')
     and p.prosecdef
     and p.prorettype = 'jsonb'::regtype
     and 'search_path=public' = any(p.proconfig)
     and 'lock_timeout=10s' = any(p.proconfig))
  and has_function_privilege('service_role', 'public.apply_erp_item_updates(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.apply_erp_item_updates(jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.apply_erp_item_updates(jsonb)', 'execute')
  and exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20261011170134'
  )
) as passed;
