-- shared-db#4281 (claim #4283) live proof (read-only), on the #4168 pattern. Proves:
-- each function exists on its own as SECURITY DEFINER with an empty search_path and
-- its exact return type/volatility (get: STABLE text; set: VOLATILE void), execute is
-- service_role only, anon/authenticated cannot read vault.secrets or
-- vault.decrypted_secrets, the Vault secret popdam_render_z_nas_password exists (the
-- migration's verified copy created it), and the migration is in the ledger.
-- The secret value is never read.
select (
  (select count(*) = 1 from pg_proc p
    where p.oid = to_regprocedure('public.get_render_z_nas_password()')
      and p.prosecdef and p.provolatile = 's' and p.prorettype = 'text'::regtype
      and 'search_path=""' = any(p.proconfig))
  and (select count(*) = 1 from pg_proc p
    where p.oid = to_regprocedure('public.set_render_z_nas_password(text)')
      and p.prosecdef and p.provolatile = 'v' and p.prorettype = 'void'::regtype
      and 'search_path=""' = any(p.proconfig))
  and has_function_privilege('service_role', 'public.get_render_z_nas_password()', 'execute')
  and has_function_privilege('service_role', 'public.set_render_z_nas_password(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.get_render_z_nas_password()', 'execute')
  and not has_function_privilege('anon', 'public.get_render_z_nas_password()', 'execute')
  and not has_function_privilege('authenticated', 'public.set_render_z_nas_password(text)', 'execute')
  and not has_function_privilege('anon', 'public.set_render_z_nas_password(text)', 'execute')
  and exists (select 1 from vault.secrets where name = 'popdam_render_z_nas_password')
  and not has_table_privilege('anon', 'vault.secrets', 'select')
  and not has_table_privilege('authenticated', 'vault.secrets', 'select')
  and not has_table_privilege('anon', 'vault.decrypted_secrets', 'select')
  and not has_table_privilege('authenticated', 'vault.decrypted_secrets', 'select')
  and exists (
    select 1 from supabase_migrations.schema_migrations
    where version = '20261014043757'
  )
) as passed;
