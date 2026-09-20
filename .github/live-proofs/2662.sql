-- Bounded six-view outcome only; does not close all issue #2662 findings.
SELECT count(*) = 6
   AND bool_and(c.relkind = 'v'
     AND NOT has_table_privilege('authenticated', c.oid, 'SELECT')
     AND has_table_privilege('service_role', c.oid, 'SELECT')) as passed
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'api'
  AND c.relname IN ('crm_factory_picker_list', 'opa_disney_property', 'opa_lucasfilm_property', 'opa_marvel_property', 'pm_factory_list', 'source_capture_inventory');
