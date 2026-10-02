-- =====================================================================================
-- Issue #3882 child 2 - repoint 14 dflow foreign keys to the parents the DesignFlow
-- Cloud SQL cutover actually loads.
--
-- Claim: #3884. Reserved version 20261002155049.
--
-- WHY: the cutover maps art_piece, properties_and_characters,
-- property_character_associations and item_character_associations to dflow, but
-- loads their parents into core."merchGroup", core."licenseList", plm."divisionCode",
-- plm."SeasonCode" and plm."itemHeader". The dflow copies' FKs still point at stale
-- dflow parents. Design: #3882 comment 5955949106.
--
-- STRUCTURE ONLY. Each FK is dropped and re-added under the same name, same column,
-- same ON UPDATE/ON DELETE actions; only the referenced table changes. Live check
-- 2026-10-02 on production: zero existing child rows orphan against the new parents,
-- so the constraints are added validated.
--
-- Not here: plm.art_piece_attachment and app."RolePermissions" (frozen-schema
-- repoints) belong to open PR #3391 (#2110), which performs those exact swaps.
-- =====================================================================================

-- derived-from: none

alter table dflow.art_piece drop constraint art_piece_licensor_id_fkey;
alter table dflow.art_piece add constraint art_piece_licensor_id_fkey
  foreign key (licensor_id) references core."merchGroup"(mg_id);
alter table dflow.art_piece drop constraint art_piece_property_id_fkey;
alter table dflow.art_piece add constraint art_piece_property_id_fkey
  foreign key (property_id) references core."merchGroup"(mg_id);
alter table dflow.art_piece drop constraint art_piece_style_guide_id_fkey;
alter table dflow.art_piece add constraint art_piece_style_guide_id_fkey
  foreign key (style_guide_id) references core."merchGroup"(mg_id);
alter table dflow.art_piece drop constraint art_piece_big_theme_id_fkey;
alter table dflow.art_piece add constraint art_piece_big_theme_id_fkey
  foreign key (big_theme_id) references core."merchGroup"(mg_id);
alter table dflow.art_piece drop constraint art_piece_little_theme_id_fkey;
alter table dflow.art_piece add constraint art_piece_little_theme_id_fkey
  foreign key (little_theme_id) references core."merchGroup"(mg_id);
alter table dflow.art_piece drop constraint art_piece_art_type_id_fkey;
alter table dflow.art_piece add constraint art_piece_art_type_id_fkey
  foreign key (art_type_id) references core."merchGroup"(mg_id);
alter table dflow.art_piece drop constraint art_piece_art_source_id_fkey;
alter table dflow.art_piece add constraint art_piece_art_source_id_fkey
  foreign key (art_source_id) references core."merchGroup"(mg_id);
alter table dflow.art_piece drop constraint art_piece_artist_id_fkey;
alter table dflow.art_piece add constraint art_piece_artist_id_fkey
  foreign key (artist_id) references core."merchGroup"(mg_id);
alter table dflow.art_piece drop constraint art_piece_age_group_id_fkey;
alter table dflow.art_piece add constraint art_piece_age_group_id_fkey
  foreign key (age_group_id) references core."merchGroup"(mg_id);
alter table dflow.art_piece drop constraint art_piece_divisioncode_id_fkey;
alter table dflow.art_piece add constraint art_piece_divisioncode_id_fkey
  foreign key (divisioncode_id) references plm."divisionCode"("divCode_id");
alter table dflow.art_piece drop constraint art_piece_season_code_id_fkey;
alter table dflow.art_piece add constraint art_piece_season_code_id_fkey
  foreign key (season_code_id) references plm."SeasonCode"(id);
alter table dflow.properties_and_characters drop constraint properties_and_characters_licensor_id_fkey;
alter table dflow.properties_and_characters add constraint properties_and_characters_licensor_id_fkey
  foreign key (licensor_id) references core."licenseList"("licenseList_id") on update cascade on delete restrict;
alter table dflow.property_character_associations drop constraint property_character_associations_licensor_id_fkey;
alter table dflow.property_character_associations add constraint property_character_associations_licensor_id_fkey
  foreign key (licensor_id) references core."licenseList"("licenseList_id") on update cascade on delete restrict;
alter table dflow.item_character_associations drop constraint item_character_associations_item_header_id_fkey;
alter table dflow.item_character_associations add constraint item_character_associations_item_header_id_fkey
  foreign key (item_header_id) references plm."itemHeader"(item_id_pk) on update cascade on delete cascade;
