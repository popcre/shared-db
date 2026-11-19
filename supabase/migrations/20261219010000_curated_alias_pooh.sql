-- Curated alias (shared-db #6781, popdam3#1037): "Pooh" names the Disney character "Winnie The Pooh".
-- One row only. Fails closed if the parent is unavailable or any licensor already has a matching alias.
do $curation$
declare
  target_id constant uuid := 'c80171c3-cd42-4d61-9a98-177e83ce0917';
  target_licensor uuid;
begin
  -- Keep the global alias check and insert atomic with respect to alias writers.
  lock table core.character_alias in share row exclusive mode;
  select c.licensor_id into target_licensor from core."character" c
    where c.id = target_id and c.name = 'Winnie The Pooh' for share;
  if target_licensor is null then
    raise exception 'Winnie The Pooh parent unavailable; alias abstained';
  end if;
  -- Match both the stored alias key and the unscoped DAM named search key.
  if exists (select 1 from core.character_alias a
      where a.normalized_alias = 'pooh'
         or btrim(regexp_replace(lower(replace(replace(a.alias, U&'\0130', 'i '), U&'\212A', 'k') collate pg_catalog."C"), '[^a-z0-9]+', ' ', 'g')) = 'pooh') then
    raise exception 'A character alias already matches pooh; alias abstained';
  end if;
  insert into core.character_alias (character_id, licensor_id, alias, source_system, evidence_notes, created_by, updated_by)
  values (target_id, target_licensor, 'Pooh', 'popdam3#1037',
    'Common short name used in PopDAM search (shared-db #6781)', 'shared-db migration 20261219010000', 'shared-db migration 20261219010000');
end $curation$;
