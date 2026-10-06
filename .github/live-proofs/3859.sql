-- Live proof for #3859 (migration 20261001122410, PR #3862). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. index prod_detail_company_code_prod_order_no_idx exists on coldlion.prod_detail
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261001122410')
  and exists (
    select 1 from pg_catalog.pg_class
    where oid = pg_catalog.to_regclass('coldlion.prod_detail_company_code_prod_order_no_idx')
      and relkind = 'i'
  )
) as passed;
