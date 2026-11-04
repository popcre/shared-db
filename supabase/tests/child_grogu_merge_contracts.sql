-- popdam3#680 / review finding #5549: run after the merge migration.
do $contracts$
begin
  if not exists (
    select 1 from core."character" child
    join core."character" grogu on grogu.licensor_id = child.licensor_id
    where child.id = '0e5896e5-7813-4f82-a428-d4669504100a'
      and grogu.id = '5183540b-1ae9-4eeb-9efc-b638deda17ac'
      and child.status = 'inactive' and grogu.status = 'active'
  ) then raise exception 'Both identities must survive within one licensor'; end if;

  if not exists (
    select 1 from core.character_alias
    where character_id = '5183540b-1ae9-4eeb-9efc-b638deda17ac'
      and normalized_alias = core.normalize_popsg_property_observation('Child')
  ) or exists (
    select 1 from core.character_alias
    where character_id = '0e5896e5-7813-4f82-a428-d4669504100a'
  ) then raise exception 'Child aliases must resolve to Grogu'; end if;

  if exists (
    select 1 from archive.character_child_grogu_merge_20261104 s
    where s.source_table = 'core.character_alias'
      and not exists (
        select 1 from core.character_alias a
        where a.id = (s.old_row->>'id')::uuid
          and a.character_id = '5183540b-1ae9-4eeb-9efc-b638deda17ac'
          and a.alias = s.old_row->>'alias'
          and a.source_system = s.old_row->>'source_system'
      )
  ) then raise exception 'Archived aliases must retain identity and provenance'; end if;

  if exists (
    select 1 from public.asset_licensor_characters
    where character_id = '0e5896e5-7813-4f82-a428-d4669504100a'
  ) or exists (
    select 1 from archive.character_child_grogu_merge_20261104 s
    where s.source_table = 'public.asset_licensor_characters'
      and not exists (
        select 1 from public.asset_licensor_characters a
        where a.asset_id = (s.old_row->>'asset_id')::uuid
          and a.character_id = '5183540b-1ae9-4eeb-9efc-b638deda17ac'
      )
  ) then raise exception 'All archived asset tags must survive on Grogu'; end if;

  if (select count(*) from archive.character_child_grogu_merge_20261104
      where source_table = 'core.character') <> 2
    or not (select relrowsecurity from pg_class
      where oid = 'archive.character_child_grogu_merge_20261104'::regclass)
    or not exists (select 1 from pg_constraint
      where conrelid = 'archive.character_child_grogu_merge_20261104'::regclass
        and contype = 'p')
  then raise exception 'Recovery archive must hold both identities with a primary key and RLS'; end if;
end
$contracts$;
