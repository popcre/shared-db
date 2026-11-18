BEGIN;

DO $test$
DECLARE
  backend CONSTANT name := 'designflow_prod_backend_runtime';
  reader CONSTANT name := 'designflow_property_suggestion_reader';
  helper CONSTANT regprocedure := 'plm_property_suggestion_private.lookup(text)'::regprocedure;
  entrypoint CONSTANT regprocedure := 'plm.suggested_property_for_sku(text)'::regprocedure;
  original CONSTANT regprocedure := 'plm.suggested_property_for_sku_invoker(text)'::regprocedure;
  source regclass;
  actor name;
  matches bigint;
BEGIN
  ASSERT EXISTS (
    SELECT FROM pg_roles
    WHERE rolname = reader
      AND NOT (rolcanlogin OR rolinherit OR rolsuper OR rolcreatedb
        OR rolcreaterole OR rolreplication OR rolbypassrls)
  ), 'lookup owner must be a restricted non-login role';
  ASSERT EXISTS (
    SELECT FROM pg_proc
    WHERE oid = helper AND prosecdef AND proisstrict AND provolatile = 's'
      AND proowner = reader::regrole AND proconfig = ARRAY['search_path=pg_catalog, pg_temp']
  ), 'helper must be stable with an isolated owner and search path';
  ASSERT (SELECT NOT prosecdef FROM pg_proc WHERE oid = entrypoint),
    'existing user-facing signature must remain security invoker';
  ASSERT (SELECT NOT prosecdef AND md5(prosrc) = '5a545f4b0e46a3b0b596000216d92163'
          FROM pg_proc WHERE oid = original),
    'legacy users must retain the exact component-scoped invoker query';
  ASSERT NOT has_function_privilege('public', helper, 'EXECUTE'),
    'PUBLIC must not execute the helper';

  FOREACH actor IN ARRAY ARRAY['anon', 'authenticated', 'service_role']::name[] LOOP
    ASSERT NOT has_schema_privilege(actor, 'plm_property_suggestion_private', 'USAGE')
       AND NOT has_function_privilege(actor, helper, 'EXECUTE'),
      'API roles must not reach the helper';
  END LOOP;
  ASSERT NOT has_function_privilege('anon', entrypoint, 'EXECUTE')
     AND has_function_privilege('authenticated', entrypoint, 'EXECUTE')
     AND has_function_privilege('service_role', entrypoint, 'EXECUTE'),
    'existing function grants must retain their authorized callers';

  IF EXISTS (SELECT FROM pg_roles WHERE rolname = backend) THEN
    ASSERT has_function_privilege(backend, entrypoint, 'EXECUTE')
       AND NOT has_function_privilege(backend, original, 'EXECUTE')
       AND NOT pg_has_role(backend, reader, 'MEMBER'),
      'backend must call only the scoped lookup without assuming its owner';
    FOREACH source IN ARRAY ARRAY[
      'plm.coldlion_item_merch_group', 'plm.dcp_asset', 'plm.dcp_asset_property_observation',
      'plm.dcp_property', 'plm.dcp_property_mg06_crosswalk',
      'public.sku_files_used', 'public.style_guide_files'
    ]::regclass[] LOOP
      ASSERT NOT has_any_column_privilege(backend, source, 'SELECT, INSERT, UPDATE')
         AND NOT has_table_privilege(backend, source, 'DELETE, TRUNCATE, TRIGGER'),
        'backend must not gain direct source access on ' || source;
      ASSERT NOT has_table_privilege(reader, source, 'SELECT, DELETE, TRUNCATE, TRIGGER')
         AND NOT has_any_column_privilege(reader, source, 'INSERT, UPDATE'),
        'lookup owner must have column reads only on ' || source;
    END LOOP;

    SET LOCAL ROLE designflow_prod_backend_runtime;
    SELECT count(*) INTO matches FROM plm.suggested_property_for_sku('NO-SUCH-SKU-6693');
    RESET ROLE;
    ASSERT matches = 0, 'unknown SKU must return no suggestions as the backend login';
  END IF;
END
$test$;

ROLLBACK;
