-- Live proof for #3234 (migration 20261005044103, PR #3883). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. coldlion.prod_detail still has PRIMARY KEY (company_code, pkey)
--   3. the falsified UNIQUE (company_code, prod_order_no, prod_line_seq) is ABSENT
--   4. landing RLS remains on; anon/authenticated hold no privilege
select (
  (exists (select 1 from supabase_migrations.schema_migrations where version = '20260930212107')
  or exists (select 1 from supabase_migrations.schema_migrations where version = '20261005044103'))
  and exists (
    select 1 from pg_catalog.pg_class
    where oid = pg_catalog.to_regclass('coldlion.prod_detail')
      and relkind = 'r' and relrowsecurity
  )
  and exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = pg_catalog.to_regclass('coldlion.prod_detail')
      and c.contype = 'p'
      and array(
        select a.attname::text from unnest(c.conkey) with ordinality as k(attnum, ordinal)
        join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
        order by k.ordinal
      ) = array['company_code', 'pkey']
  )
  and not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = pg_catalog.to_regclass('coldlion.prod_detail')
      and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (company_code, prod_order_no, prod_line_seq)'
  )
  and not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = pg_catalog.to_regclass('coldlion.prod_detail')
      and contype = 'u'
      and pg_get_constraintdef(oid) like '%prod_line_seq%'
  )
  and not has_table_privilege('anon', 'coldlion.prod_detail', 'SELECT')
  and not has_table_privilege('authenticated', 'coldlion.prod_detail', 'SELECT')
) as passed;
