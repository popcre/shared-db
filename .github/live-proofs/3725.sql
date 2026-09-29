-- #3725 read-only production proof: plm.wb_validate_normalized_row(text,jsonb)
-- is STABLE after 20260929005943, with body, search_path, security mode,
-- return type and grants unchanged.
SELECT (
  EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE version = '20260929005943'
  )
  AND EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid = pg_catalog.to_regprocedure('plm.wb_validate_normalized_row(text,jsonb)')
      AND p.provolatile = 's'
      AND NOT p.prosecdef
      AND p.prorettype = 'void'::regtype
      AND p.proconfig = ARRAY['search_path=pg_catalog']
      AND pg_catalog.md5(p.prosrc) = 'e28fedd3c0534399a3d890f5cf69a9ec'
      AND NOT pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      AND NOT pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
  )
) as passed;
