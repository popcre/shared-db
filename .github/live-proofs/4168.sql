-- shared-db#4168 live proof (read-only). Proves: both functions exist as SECURITY
-- DEFINER with an empty search_path and the expected return types/volatility,
-- execute is service_role only, the migration is in the ledger, and the Vault secret
-- popdam_sg_nas_password exists (production holds the source admin_config row, so the
-- migration's verified copy must have created it). The secret value is never read.
select (
  (select count(*) = 1 from pg_proc p
    where p.oid = to_regprocedure('public.get_sg_nas_password()')
      and p.prosecdef and p.provolatile = 's' and p.prorettype = 'text'::regtype
      and 'search_path=""' = any(p.proconfig))
  and (select count(*) = 1 from pg_proc p
    where p.oid = to_regprocedure('public.set_sg_nas_password(text)')
      and p.prosecdef and p.provolatile = 'v' and p.prorettype = 'void'::regtype
      and 'search_path=""' = any(p.proconfig))
  and has_function_privilege('service_role', 'public.get_sg_nas_password()', 'execute')
  and has_function_privilege('service_role', 'public.set_sg_nas_password(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_sg_nas_password()', 'execute')
  and not has_function_privilege('anon', 'public.get_sg_nas_password()', 'execute')
  and not has_function_privilege('authenticated', 'public.set_sg_nas_password(text)', 'execute')
  and not has_function_privilege('anon', 'public.set_sg_nas_password(text)', 'execute')
  and exists (select 1 from vault.secrets where name = 'popdam_sg_nas_password')
  and not has_table_privilege('anon', 'vault.secrets', 'select')
  and not has_table_privilege('authenticated', 'vault.secrets', 'select')
  and not has_table_privilege('anon', 'vault.decrypted_secrets', 'select')
  and not has_table_privilege('authenticated', 'vault.decrypted_secrets', 'select')
  and exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20261011211208'
  )
) as passed;
