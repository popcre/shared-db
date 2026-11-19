-- Live proof for #2860 (migration 20260915111626). Read-only.
-- Proves on production, by exact match against
-- supabase/migrations/20260915111626_popsg_search_v2_default_timeout.sql:
--   1. the migration is in production's ledger;
--   2. public.search_style_guide_library_v2 with the 15-argument signature is
--      SECURITY DEFINER, STABLE, returns jsonb, has exactly the settings
--      search_path=pg_catalog, auth and work_mem=64MB, and its body is
--      byte-identical to the migration's $function$ body
--      (md5 719d560bf41d61c8441aa806eb9406fa);
--   3. anon cannot execute it; authenticated and service_role can.
with fn as (
  select p.oid, p.prosecdef, p.provolatile, p.proconfig, pg_get_function_result(p.oid) as result, md5(p.prosrc) as body_md5
  from pg_proc p
  where p.oid = to_regprocedure(
    'public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)'
  )
)
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260915111626')
  and (select count(*) from fn
       where prosecdef
         and provolatile = 's'
         and proconfig = array['search_path=pg_catalog, auth', 'work_mem=64MB']
         and result = 'jsonb'
         and body_md5 = '719d560bf41d61c8441aa806eb9406fa'
         and not has_function_privilege('anon', oid, 'EXECUTE')
         and has_function_privilege('authenticated', oid, 'EXECUTE')
         and has_function_privilege('service_role', oid, 'EXECUTE')) = 1
) as passed
