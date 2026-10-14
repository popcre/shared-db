-- #4281 / #4283: catalog-only proof for the Z: NAS password Vault RPCs. Reads no secret value.
select (
  select bool_and(p.prosecdef and p.provolatile in ('s','v') and p.proconfig = array['search_path=""']
    and has_function_privilege('service_role', p.oid, 'EXECUTE')
    and not has_function_privilege('anon', p.oid, 'EXECUTE')
    and not has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  from pg_catalog.pg_proc p
  where p.oid in (to_regprocedure('public.get_render_z_nas_password()'), to_regprocedure('public.set_render_z_nas_password(text)'))
) is true
  and not has_table_privilege('anon', 'vault.secrets', 'select')
  and not has_table_privilege('authenticated', 'vault.secrets', 'select')
  and exists (select 1 from supabase_migrations.schema_migrations where version = '20261014043757')
  as passed;
