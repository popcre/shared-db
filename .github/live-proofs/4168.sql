select (
  (select count(*) = 2
   from pg_proc p
   where p.oid in (to_regprocedure('public.get_sg_nas_password()'),
                   to_regprocedure('public.set_sg_nas_password(text)'))
     and p.prosecdef
     and 'search_path=""' = any(p.proconfig))
  and has_function_privilege('service_role', 'public.get_sg_nas_password()', 'execute')
  and has_function_privilege('service_role', 'public.set_sg_nas_password(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_sg_nas_password()', 'execute')
  and not has_function_privilege('anon', 'public.get_sg_nas_password()', 'execute')
  and not has_function_privilege('authenticated', 'public.set_sg_nas_password(text)', 'execute')
  and not has_function_privilege('anon', 'public.set_sg_nas_password(text)', 'execute')
  and exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20261011170328'
  )
) as passed;
