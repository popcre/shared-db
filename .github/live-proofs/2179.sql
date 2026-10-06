-- Live proof for #2179 (migration 20260929093750, PR #3711). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. coldlion.item_image_metadata exists as a table with RLS on and 19 columns (14 source + 5 provenance)
--   3. its primary key is (company_code, pkey)
--   4. its only foreign key is run_id -> coldlion.sync_run(id) (exact definition)
--   5. anon and authenticated hold no privilege; service_role holds SELECT
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260929093750')
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
  and (
    select count(*) from pg_catalog.pg_attribute
    where attrelid = pg_catalog.to_regclass('coldlion.item_image_metadata')
      and attnum > 0 and not attisdropped
      and attname in ('company_code','pkey','resource_id','division_code','item_no',
                      'color_code','label_code','file_name','file_type','item_image_desc',
                      'created_time','created_user','mod_time','mod_user',
                      'run_id','fetched_at','source_hash','first_seen_at','last_seen_at')
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
  and exists (
    select 1 from pg_catalog.pg_constraint c
    join pg_catalog.pg_class rt on rt.oid = c.confrelid
    join pg_catalog.pg_namespace rn on rn.oid = rt.relnamespace
    where c.conrelid = pg_catalog.to_regclass('coldlion.item_image_metadata')
      and c.contype = 'f'
      and rn.nspname = 'coldlion' and rt.relname = 'sync_run'
      and pg_catalog.pg_get_constraintdef(c.oid) ~ 'FOREIGN KEY [(]run_id[)] REFERENCES coldlion[.]sync_run[(]id[)]'
  )
  and not exists (
    select 1 from pg_catalog.pg_constraint c
    join pg_catalog.pg_class rt on rt.oid = c.confrelid
    join pg_catalog.pg_namespace rn on rn.oid = rt.relnamespace
    where c.conrelid = pg_catalog.to_regclass('coldlion.item_image_metadata')
      and c.contype = 'f'
      and (rn.nspname <> 'coldlion' or rt.relname <> 'sync_run')
  )
  and (
    select count(*) from pg_catalog.pg_constraint c
    where c.conrelid = pg_catalog.to_regclass('coldlion.item_image_metadata')
      and c.contype = 'f'
  ) = 1
  and not exists (
    select 1 from unnest(array['anon', 'authenticated']) r(role_name)
    cross join unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p(privilege_name)
    where pg_catalog.has_table_privilege(r.role_name, 'coldlion.item_image_metadata', p.privilege_name)
  )
  and pg_catalog.has_table_privilege('service_role', 'coldlion.item_image_metadata', 'SELECT')
  and exists (
    select 1 from pg_catalog.pg_class i
    join pg_catalog.pg_index x on x.indexrelid = i.oid
    where i.relname = 'item_image_metadata_pkey_idx'
      and x.indrelid = pg_catalog.to_regclass('coldlion.item_image_metadata')
      and pg_catalog.pg_get_indexdef(i.oid) ~ '[(]pkey[)]'
  )
  and exists (
    select 1 from pg_catalog.pg_class i
    join pg_catalog.pg_index x on x.indexrelid = i.oid
    where i.relname = 'item_image_metadata_run_id_idx'
      and x.indrelid = pg_catalog.to_regclass('coldlion.item_image_metadata')
      and pg_catalog.pg_get_indexdef(i.oid) ~ '[(]run_id[)]'
  )
) as passed
