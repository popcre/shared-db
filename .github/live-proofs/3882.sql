-- Live proof for #3882 child 2 (migration 20261002155049). Read-only.
-- Proves on production: the migration is in the ledger and all 14 foreign keys
-- reference their mapped parents, are validated, and keep their actions.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261002155049')
  and (
    select count(*) from pg_catalog.pg_constraint c
    where c.contype = 'f' and c.convalidated
      and (c.conrelid, c.conname, c.confrelid) in (
        select pg_catalog.to_regclass(t), n, pg_catalog.to_regclass(p) from (values
          ('dflow.art_piece', 'art_piece_licensor_id_fkey', 'core."merchGroup"'),
          ('dflow.art_piece', 'art_piece_property_id_fkey', 'core."merchGroup"'),
          ('dflow.art_piece', 'art_piece_style_guide_id_fkey', 'core."merchGroup"'),
          ('dflow.art_piece', 'art_piece_big_theme_id_fkey', 'core."merchGroup"'),
          ('dflow.art_piece', 'art_piece_little_theme_id_fkey', 'core."merchGroup"'),
          ('dflow.art_piece', 'art_piece_art_type_id_fkey', 'core."merchGroup"'),
          ('dflow.art_piece', 'art_piece_art_source_id_fkey', 'core."merchGroup"'),
          ('dflow.art_piece', 'art_piece_artist_id_fkey', 'core."merchGroup"'),
          ('dflow.art_piece', 'art_piece_age_group_id_fkey', 'core."merchGroup"'),
          ('dflow.art_piece', 'art_piece_divisioncode_id_fkey', 'plm."divisionCode"'),
          ('dflow.art_piece', 'art_piece_season_code_id_fkey', 'plm."SeasonCode"'),
          ('dflow.properties_and_characters', 'properties_and_characters_licensor_id_fkey', 'core."licenseList"'),
          ('dflow.property_character_associations', 'property_character_associations_licensor_id_fkey', 'core."licenseList"'),
          ('dflow.item_character_associations', 'item_character_associations_item_header_id_fkey', 'plm."itemHeader"')
        ) v(t, n, p)
      )
  ) = 14
  and (
    select count(*) from pg_catalog.pg_constraint c
    where c.contype = 'f'
      and c.conname in ('properties_and_characters_licensor_id_fkey', 'property_character_associations_licensor_id_fkey')
      and c.conrelid in (pg_catalog.to_regclass('dflow.properties_and_characters'), pg_catalog.to_regclass('dflow.property_character_associations'))
      and c.confupdtype = 'c' and c.confdeltype = 'r'
  ) = 2
  and exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = pg_catalog.to_regclass('dflow.item_character_associations')
      and c.conname = 'item_character_associations_item_header_id_fkey'
      and c.confupdtype = 'c' and c.confdeltype = 'c'
  )
) as passed;
