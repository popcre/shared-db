-- Live proof for #3910 (migration 20261002224520, PR #3932). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. plm.import_item_master_data keeps SECURITY DEFINER, its search_path and signature
--   3. its body carries the three #3910 changes: the plm.item no-churn guard, the
--      EDGEHOME/EP001 retirement carve-out, and the reviewed-decision protection
--   4. anon and authenticated cannot execute it; service_role can
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261002224520')
  and exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure('plm.import_item_master_data(jsonb)')
      and p.prosecdef
      and p.proconfig = array['search_path=app, core, ingest, plm, extensions, public']
      and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'import_payload jsonb'
      and p.prosrc like '%plm.item.property_id,plm.item.status,plm.item.raw)%is distinct from%'
      and p.prosrc like '%<> (''EDGEHOME'', ''EP001'')%'
      and p.prosrc like '%would delete reviewed disagreement decisions%'
  )
  and not pg_catalog.has_function_privilege('anon', 'plm.import_item_master_data(jsonb)', 'execute')
  and not pg_catalog.has_function_privilege('authenticated', 'plm.import_item_master_data(jsonb)', 'execute')
  and pg_catalog.has_function_privilege('service_role', 'plm.import_item_master_data(jsonb)', 'execute')
) as passed
