-- Live proof for #3882 child 2 (migration 20261002155049). Read-only.
-- Proves on production: the migration is in the ledger and each of the 14 foreign
-- keys is validated, single-column, on the expected child column, references the
-- mapped parent's expected key column, and keeps its ON UPDATE/ON DELETE actions.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261002155049')
  and (
    select count(*) from (values
      ('dflow.art_piece', 'art_piece_licensor_id_fkey', 'licensor_id', 'core."merchGroup"', 'mg_id', 'a', 'a'),
      ('dflow.art_piece', 'art_piece_property_id_fkey', 'property_id', 'core."merchGroup"', 'mg_id', 'a', 'a'),
      ('dflow.art_piece', 'art_piece_style_guide_id_fkey', 'style_guide_id', 'core."merchGroup"', 'mg_id', 'a', 'a'),
      ('dflow.art_piece', 'art_piece_big_theme_id_fkey', 'big_theme_id', 'core."merchGroup"', 'mg_id', 'a', 'a'),
      ('dflow.art_piece', 'art_piece_little_theme_id_fkey', 'little_theme_id', 'core."merchGroup"', 'mg_id', 'a', 'a'),
      ('dflow.art_piece', 'art_piece_art_type_id_fkey', 'art_type_id', 'core."merchGroup"', 'mg_id', 'a', 'a'),
      ('dflow.art_piece', 'art_piece_art_source_id_fkey', 'art_source_id', 'core."merchGroup"', 'mg_id', 'a', 'a'),
      ('dflow.art_piece', 'art_piece_artist_id_fkey', 'artist_id', 'core."merchGroup"', 'mg_id', 'a', 'a'),
      ('dflow.art_piece', 'art_piece_age_group_id_fkey', 'age_group_id', 'core."merchGroup"', 'mg_id', 'a', 'a'),
      ('dflow.art_piece', 'art_piece_divisioncode_id_fkey', 'divisioncode_id', 'plm."divisionCode"', 'divCode_id', 'a', 'a'),
      ('dflow.art_piece', 'art_piece_season_code_id_fkey', 'season_code_id', 'plm."SeasonCode"', 'id', 'a', 'a'),
      ('dflow.properties_and_characters', 'properties_and_characters_licensor_id_fkey', 'licensor_id', 'core."licenseList"', 'licenseList_id', 'c', 'r'),
      ('dflow.property_character_associations', 'property_character_associations_licensor_id_fkey', 'licensor_id', 'core."licenseList"', 'licenseList_id', 'c', 'r'),
      ('dflow.item_character_associations', 'item_character_associations_item_header_id_fkey', 'item_header_id', 'plm."itemHeader"', 'item_id_pk', 'c', 'c')
    ) v(t, n, col, p, pc, upd, del)
    join pg_catalog.pg_constraint c
      on c.contype = 'f' and c.convalidated
     and c.conrelid = pg_catalog.to_regclass(v.t) and c.conname = v.n
     and c.confrelid = pg_catalog.to_regclass(v.p)
     and c.confupdtype = v.upd and c.confdeltype = v.del and not c.condeferrable
     and array_length(c.conkey, 1) = 1 and array_length(c.confkey, 1) = 1
    join pg_catalog.pg_attribute ca on ca.attrelid = c.conrelid and ca.attnum = c.conkey[1] and ca.attname = v.col
    join pg_catalog.pg_attribute pa on pa.attrelid = c.confrelid and pa.attnum = c.confkey[1] and pa.attname = v.pc
  ) = 14
) as passed;
