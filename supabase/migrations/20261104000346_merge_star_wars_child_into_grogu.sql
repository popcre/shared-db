-- popdam3#680: retain the Child identity for restrictive references, but retire it
-- from active use. Resolve its aliases and asset tags to Grogu. Snapshot every
-- changed row (including existing Grogu tags) so overlapping tags can be undone.
begin;

lock table core."character", core.character_alias,
  public.asset_licensor_characters in share row exclusive mode;

do $preconditions$
declare
  child_licensor uuid;
  grogu_licensor uuid;
begin
  select licensor_id into child_licensor from core."character"
  where id = '0e5896e5-7813-4f82-a428-d4669504100a';
  if not found then raise exception 'Child identity is missing; refusing merge'; end if;
  select licensor_id into grogu_licensor from core."character"
  where id = '5183540b-1ae9-4eeb-9efc-b638deda17ac' and status = 'active';
  if not found then raise exception 'Active Grogu identity is missing; refusing merge'; end if;
  if child_licensor is null or child_licensor is distinct from grogu_licensor then
    raise exception 'Child and Grogu must share a non-null licensor';
  end if;
  if exists (
    select 1 from core.character_alias
    where licensor_id = grogu_licensor
      and normalized_alias = core.normalize_popsg_property_observation('Child')
      and character_id not in ('0e5896e5-7813-4f82-a428-d4669504100a',
                              '5183540b-1ae9-4eeb-9efc-b638deda17ac')
  ) then raise exception 'Child alias resolves to a third identity; refusing merge'; end if;
end
$preconditions$;

-- Intentionally no IF NOT EXISTS: an existing snapshot must never conceal a
-- partial/incorrect earlier run or be overwritten by a retry.
create table archive.character_child_grogu_merge_20261104 (
  source_table text not null,
  row_key text not null,
  old_row jsonb not null,
  archived_at timestamptz not null default now(),
  primary key (source_table, row_key)
);
alter table archive.character_child_grogu_merge_20261104 enable row level security;

insert into archive.character_child_grogu_merge_20261104 (source_table, row_key, old_row)
select 'core.character', c.id::text, to_jsonb(c) from core."character" c
where c.id in ('0e5896e5-7813-4f82-a428-d4669504100a', '5183540b-1ae9-4eeb-9efc-b638deda17ac')
union all
select 'core.character_alias', a.id::text, to_jsonb(a) from core.character_alias a
where a.character_id in ('0e5896e5-7813-4f82-a428-d4669504100a', '5183540b-1ae9-4eeb-9efc-b638deda17ac')
union all
select 'public.asset_licensor_characters', l.asset_id::text || ':' || l.character_id::text, to_jsonb(l)
from public.asset_licensor_characters l
where l.character_id in ('0e5896e5-7813-4f82-a428-d4669504100a', '5183540b-1ae9-4eeb-9efc-b638deda17ac');

insert into public.asset_licensor_characters (asset_id, character_id, source, model, tagged_at)
select l.asset_id, '5183540b-1ae9-4eeb-9efc-b638deda17ac', l.source, l.model, l.tagged_at
from public.asset_licensor_characters l
where l.character_id = '0e5896e5-7813-4f82-a428-d4669504100a'
on conflict (asset_id, character_id) do nothing;

update core.character_alias
set character_id = '5183540b-1ae9-4eeb-9efc-b638deda17ac'
where character_id = '0e5896e5-7813-4f82-a428-d4669504100a';

insert into core.character_alias (character_id, licensor_id, alias, source_system, evidence_notes)
select c.id, c.licensor_id, 'Child', 'popdam3#680', 'Duplicate name merged into Grogu'
from core."character" c
where c.id = '5183540b-1ae9-4eeb-9efc-b638deda17ac'
  and not exists (
    select 1 from core.character_alias x
    where x.licensor_id = c.licensor_id
      and x.normalized_alias = core.normalize_popsg_property_observation('Child')
  );

delete from public.asset_licensor_characters
where character_id = '0e5896e5-7813-4f82-a428-d4669504100a';

-- Property, item and source-resolution references remain valid on the retired
-- identity; never delete a canonical character underneath restrictive dependents.
update core."character" set status = 'inactive'
where id = '0e5896e5-7813-4f82-a428-d4669504100a';

do $postconditions$
begin
  if not exists (select 1 from core."character"
    where id = '0e5896e5-7813-4f82-a428-d4669504100a' and status = 'inactive')
    or not exists (select 1 from core.character_alias
      where character_id = '5183540b-1ae9-4eeb-9efc-b638deda17ac'
        and normalized_alias = core.normalize_popsg_property_observation('Child'))
    or exists (select 1 from core.character_alias
      where character_id = '0e5896e5-7813-4f82-a428-d4669504100a')
    or exists (select 1 from public.asset_licensor_characters
      where character_id = '0e5896e5-7813-4f82-a428-d4669504100a')
    or exists (
      select 1 from archive.character_child_grogu_merge_20261104 s
      where s.source_table = 'public.asset_licensor_characters'
        and s.old_row->>'character_id' = '0e5896e5-7813-4f82-a428-d4669504100a'
        and not exists (select 1 from public.asset_licensor_characters l
          where l.asset_id = (s.old_row->>'asset_id')::uuid
            and l.character_id = '5183540b-1ae9-4eeb-9efc-b638deda17ac')
    ) then raise exception 'Child to Grogu merge postconditions failed';
  end if;
end
$postconditions$;

commit;
