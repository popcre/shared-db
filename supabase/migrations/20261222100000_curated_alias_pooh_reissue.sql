-- derived-from: none
-- Curated alias reissue (shared-db #6781, popdam3#1037): "Pooh" names the Disney character "Winnie The Pooh".
-- The retired 20261221010000 never applied. This standalone insert resolves the parent by
-- licensor and exact name. A missing parent is a no-op; production verification requires the row.
-- Ambiguous parents and existing Disney aliases that normalize to "pooh" abort the insert.
do $curation$
declare
  target_id uuid;
  target_licensor uuid;
begin
  begin
    select c.id, c.licensor_id into strict target_id, target_licensor
    from core."character" c join core.licensor l on l.id = c.licensor_id
    where l.name = 'DISNEY' and c.name = 'Winnie The Pooh'
    for share of c;
  exception when no_data_found then
    raise notice 'Winnie The Pooh parent absent in this database; no alias written';
    return;
  end;
  if exists (select 1 from core.character_alias a
      where a.licensor_id = target_licensor
        and a.normalized_alias = core.normalize_popsg_property_observation('Pooh')) then
    raise exception 'A Disney alias already normalizes to pooh; alias abstained';
  end if;
  insert into core.character_alias (character_id, licensor_id, alias, source_system, evidence_notes, created_by, updated_by)
  values (target_id, target_licensor, 'Pooh', 'popdam3#1037',
    'Common short name used in PopDAM search (shared-db #6781)', 'shared-db migration 20261222100000', 'shared-db migration 20261222100000');
end $curation$;
