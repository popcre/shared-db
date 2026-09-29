-- Live proof for #2179 (migration 20260929044541, PR #3711). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. coldlion.item_image_metadata exists as a table with RLS on and 19 columns (14 source + 5 provenance)
--   3. its primary key is (company_code, pkey)
--   4. anon and authenticated hold no privilege on it
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260929044541')
  and exists (
    select 1 from pg_catalog.pg_class
    where oid = pg_catalog.to_regclass('coldlion.item_image_metadata')
      and relkind = 'r' and relrowsecurity
  )
  and (
    select count(*) from pg_catalog.pg_attribute
    where attrelid = pg_catalog.to_regclass('coldlion.item_image_metadata')
      and attnum > 0 and not attisdropped
  ) = 19
  and exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = pg_catalog.to_regclass('coldlion.item_image_metadata')
      and c.contype = 'p'
      and array(
        select a.attname::text from unnest(c.conkey) with ordinality as k(attnum, ordinal)
        join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
        order by k.ordinal
      ) = array['company_code', 'pkey']
  )
  and not exists (
    select 1 from unnest(array['anon', 'authenticated']) r(role_name)
    cross join unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p(privilege_name)
    where pg_catalog.has_table_privilege(r.role_name, 'coldlion.item_image_metadata', p.privilege_name)
  )
) as passed
