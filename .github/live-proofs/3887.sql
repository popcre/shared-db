-- Live proof for #3887 (#3882 child 2b, migration 20261002155633). Read-only.
-- Proves on production: the migration is in the ledger; all 8 user foreign keys
-- reference dflow.users(id) from the same single source column, are validated, and
-- keep the exact actions they had before (pre-apply live read 2026-10-02:
-- ON UPDATE NO ACTION / ON DELETE NO ACTION for the six core constraints,
-- ON UPDATE CASCADE / ON DELETE NO ACTION for the two plm constraints); no FK on the
-- five tables still references app.users; app.users itself still exists.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261002155633')
  and pg_catalog.to_regclass('app.users') is not null
  and (
    select count(*) from pg_catalog.pg_constraint c
    where c.contype = 'f' and c.convalidated
      and c.confrelid = pg_catalog.to_regclass('dflow.users')
      and c.confdeltype = 'a'
      and c.confkey = array[(select a.attnum from pg_catalog.pg_attribute a
                             where a.attrelid = pg_catalog.to_regclass('dflow.users') and a.attname = 'id')]::int2[]
      and (c.conrelid, c.conname, c.confupdtype, c.conkey) in (
        select pg_catalog.to_regclass(t), n, u::"char",
               array[(select a.attnum from pg_catalog.pg_attribute a
                      where a.attrelid = pg_catalog.to_regclass(t) and a.attname = col)]::int2[]
        from (values
          ('core.age_group', 'age_group_created_by_fkey', 'a', 'created_by'),
          ('core.age_group', 'age_group_updated_by_fkey', 'a', 'updated_by'),
          ('core.art_types', 'art_types_created_by_fkey', 'a', 'created_by'),
          ('core.art_types', 'art_types_updated_by_fkey', 'a', 'updated_by'),
          ('core.artist_types', 'artist_types_created_by_fkey', 'a', 'created_by'),
          ('core.artist_types', 'artist_types_updated_by_fkey', 'a', 'updated_by'),
          ('plm."productUserAssignment"', 'productUserAssignment_user_id_fk_fkey', 'c', 'user_id_fk'),
          ('plm.sample_comments', 'sample_comments_user_id_fkey', 'c', 'user_id')
        ) v(t, n, u, col)
      )
  ) = 8
  and not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.contype = 'f'
      and c.confrelid = pg_catalog.to_regclass('app.users')
      and c.conrelid in (pg_catalog.to_regclass('core.age_group'), pg_catalog.to_regclass('core.art_types'),
                         pg_catalog.to_regclass('core.artist_types'), pg_catalog.to_regclass('plm."productUserAssignment"'),
                         pg_catalog.to_regclass('plm.sample_comments'))
  )
) as passed;
