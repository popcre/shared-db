-- Live proof for #3894 (migration 20261002183413). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. do_not_use_reason (text, nullable) exists on the three studio DCP asset tables
--   3. each table carries its named, validated non-whitespace CHECK on that column
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261002183413')
  and (
    select count(*) from information_schema.columns
    where table_schema = 'plm'
      and table_name in ('lucasfilm_dcp_asset', 'marvel_dcp_asset', 'twentieth_century_dcp_asset')
      and column_name = 'do_not_use_reason'
      and data_type = 'text'
      and is_nullable = 'YES'
  ) = 3
  and (
    select count(*) from pg_catalog.pg_constraint c
    where c.contype = 'c'
      and c.convalidated
      and (c.conrelid, c.conname) in (
        (pg_catalog.to_regclass('plm.lucasfilm_dcp_asset'), 'lucasfilm_dcp_asset_do_not_use_reason_chk'),
        (pg_catalog.to_regclass('plm.marvel_dcp_asset'), 'marvel_dcp_asset_do_not_use_reason_chk'),
        (pg_catalog.to_regclass('plm.twentieth_century_dcp_asset'), 'twentieth_century_dcp_asset_do_not_use_reason_chk')
      )
      -- exact, literal substring checks (strpos has no pattern syntax)
      and strpos(pg_catalog.pg_get_constraintdef(c.oid), '(do_not_use_reason IS NULL)') > 0
      and strpos(pg_catalog.pg_get_constraintdef(c.oid), '(do_not_use_reason ~ ''[^[:space:]]''::text)') > 0
  ) = 3
) as passed;
