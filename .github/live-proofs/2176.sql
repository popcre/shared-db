-- Live proof for #2176 (migration 20261005025111, PR #3839). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. schema coldlion remains closed to app roles
--   3. consumer contract views/functions exist in plm/pim
--   4. sales-history view exposes no fulfilment/status column
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261005025111')
  and not has_schema_privilege('anon', 'coldlion', 'USAGE')
  and not has_schema_privilege('authenticated', 'coldlion', 'USAGE')
  and pg_catalog.to_regclass('plm.coldlion_item_header') is not null
  and pg_catalog.to_regclass('plm.coldlion_item_detail') is not null
  and pg_catalog.to_regclass('plm.coldlion_item_merch_group') is not null
  and pg_catalog.to_regclass('plm.coldlion_prod_history') is not null
  and pg_catalog.to_regclass('plm.coldlion_prepack_detail') is not null
  and pg_catalog.to_regclass('plm.coldlion_prod_detail') is not null
  and pg_catalog.to_regclass('plm.coldlion_sales_history') is not null
  and pg_catalog.to_regclass('pim.coldlion_item_image_metadata') is not null
  and pg_catalog.to_regprocedure('plm.import_coldlion_seasons()') is not null
  and pg_catalog.to_regprocedure('plm.import_coldlion_salespersons()') is not null
  and pg_catalog.to_regprocedure('plm.coldlion_merch_group_candidates(text, text)') is not null
  and not exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = pg_catalog.to_regclass('plm.coldlion_sales_history')
      and attname in ('fulfilment_status', 'document_type', 'source_document_type', 'fulfillment_status')
  )
) as passed;
