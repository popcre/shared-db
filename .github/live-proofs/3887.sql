-- Live proof for #3887 (#3882 child 2b, migration 20261002155633). Read-only.
-- Proves on production: the migration is in the ledger and all 8 user foreign keys
-- reference dflow.users, are validated, and keep their ON UPDATE actions.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261002155633')
  and (
    select count(*) from pg_catalog.pg_constraint c
    where c.contype = 'f' and c.convalidated
      and c.confrelid = pg_catalog.to_regclass('dflow.users')
      and (c.conrelid, c.conname, c.confupdtype) in (
        select pg_catalog.to_regclass(t), n, u::"char" from (values
          ('core.age_group', 'age_group_created_by_fkey', 'a'),
          ('core.age_group', 'age_group_updated_by_fkey', 'a'),
          ('core.art_types', 'art_types_created_by_fkey', 'a'),
          ('core.art_types', 'art_types_updated_by_fkey', 'a'),
          ('core.artist_types', 'artist_types_created_by_fkey', 'a'),
          ('core.artist_types', 'artist_types_updated_by_fkey', 'a'),
          ('plm."productUserAssignment"', 'productUserAssignment_user_id_fk_fkey', 'c'),
          ('plm.sample_comments', 'sample_comments_user_id_fkey', 'c')
        ) v(t, n, u)
      )
  ) = 8
) as passed;
