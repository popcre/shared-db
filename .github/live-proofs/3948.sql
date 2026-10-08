-- Live proof for #3948 (migration 20261006004845, successor of 20261001122410). Read-only.
-- Proves on production:
--   1. the successor (or original) migration is in production's ledger
--   2. index prod_detail_company_code_prod_order_no_idx exists on coldlion.prod_detail
--      as a non-unique btree on (company_code, prod_order_no)
select (
  exists (select 1 from supabase_migrations.schema_migrations
          where version in ('20261006004845', '20261001122410'))
  and exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname = 'coldlion' and tablename = 'prod_detail'
      and indexname = 'prod_detail_company_code_prod_order_no_idx'
      and indexdef = 'CREATE INDEX prod_detail_company_code_prod_order_no_idx ON coldlion.prod_detail USING btree (company_code, prod_order_no)'
  )
) as passed;
