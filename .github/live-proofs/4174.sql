select (
  (select count(*) = 1
   from pg_proc p
   where p.oid = to_regprocedure('public.refresh_style_group_counts_serialized(uuid[])')
     and p.prosecdef
     and p.prorettype = 'integer'::regtype
     and 'lock_timeout=5s' = any(p.proconfig)
     and p.prosrc like '%pg_advisory_xact_lock(hashtext(''BULK_OPERATIONS''))%')
  and has_function_privilege('service_role', 'public.refresh_style_group_counts_serialized(uuid[])', 'execute')
  and not has_function_privilege('authenticated', 'public.refresh_style_group_counts_serialized(uuid[])', 'execute')
  and not has_function_privilege('anon', 'public.refresh_style_group_counts_serialized(uuid[])', 'execute')
  and exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20261011165708'
  )
) as passed;
