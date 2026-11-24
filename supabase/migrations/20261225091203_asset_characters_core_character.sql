-- popcre/shared-db#6995 (stage C2 of u2giants/popdam3#1298; plan_shared_data_no_copies_db.md)
-- PopDAM image character tags (public.asset_characters) stop pointing at
-- PopDAM's own list (public.characters) and point at the shared core.character,
-- through the reviewed map dam.character_core_map built in C1 (#6994).
--
--   1. full snapshot  -> archive.asset_characters_before_core_character_20261124
--   2. links whose PopDAM character has no map row are deleted (kept in the archive)
--   3. links that collapse onto the same (asset, core character) keep one row
--   4. character_id becomes core.character.id (batches of 20,000 rows)
--   5. FK -> core.character(id) on delete cascade (same as asset_licensor_characters)
--   6. dam.character_usage carries PopDAM's usage_count / is_priority per core character
--   7. search builders join asset_characters to core.character, not public.characters
--   8. search documents whose character text changed are rebuilt
--
-- public.characters / properties / licensors / dam_character_catalog stay (C4).
-- Rollback: restore public.asset_characters from the archive table and put the
-- FK back to public.characters(id); drop dam.character_usage.

-- 1. Snapshot (full copy, before anything changes).
create table archive.asset_characters_before_core_character_20261124 as
  select * from public.asset_characters;
alter table archive.asset_characters_before_core_character_20261124
  add primary key (asset_id, character_id);
revoke all on archive.asset_characters_before_core_character_20261124 from public, anon, authenticated;
comment on table archive.asset_characters_before_core_character_20261124 is
  'public.asset_characters before the core.character re-point (popcre/shared-db#6995). Rollback source.';

-- The per-statement search refresh triggers would rebuild every tagged asset
-- (~21k) inside this migration; step 8 rebuilds only documents whose text changed.
alter table public.asset_characters disable trigger asset_characters_dam_search_refresh_ins;
alter table public.asset_characters disable trigger asset_characters_dam_search_refresh_upd;
alter table public.asset_characters disable trigger asset_characters_dam_search_refresh_del;

alter table public.asset_characters drop constraint asset_characters_character_id_fkey;

-- 2. Unmapped links (still in the archive).
delete from public.asset_characters ac
where not exists (select 1 from dam.character_core_map m where m.public_character_id = ac.character_id);

-- 3. Collapse links that map to the same core character on the same asset.
delete from public.asset_characters ac
using dam.character_core_map m, public.asset_characters ac2, dam.character_core_map m2
where m.public_character_id = ac.character_id
  and ac2.asset_id = ac.asset_id
  and m2.public_character_id = ac2.character_id
  and m2.core_character_id = m.core_character_id
  and ac2.character_id < ac.character_id;

-- 4. Re-point in batches. core.character ids and public.characters ids never
--    overlap (checked on production 2026-11-24), so a remapped row is never re-read.
do $$
declare v_rows integer;
begin
  if exists (select 1 from public.characters pc join core.character c on c.id = pc.id) then
    raise exception 'C2: public.characters and core.character share ids; remap would be ambiguous';
  end if;
  loop
    with b as (
      select ac.asset_id, ac.character_id, m.core_character_id
      from public.asset_characters ac
      join dam.character_core_map m on m.public_character_id = ac.character_id
      limit 20000
    )
    update public.asset_characters ac
       set character_id = b.core_character_id
      from b
     where ac.asset_id = b.asset_id and ac.character_id = b.character_id;
    get diagnostics v_rows = row_count;
    exit when v_rows = 0;
  end loop;
end $$;

-- 5. New FK.
alter table public.asset_characters
  add constraint asset_characters_character_id_fkey
  foreign key (character_id) references core.character (id) on delete cascade;
create index if not exists asset_characters_character_id_idx on public.asset_characters (character_id);
comment on column public.asset_characters.character_id is
  'core.character.id (popcre/shared-db#6995). Before 2026-11-24 this held public.characters.id.';

alter table public.asset_characters enable trigger asset_characters_dam_search_refresh_ins;
alter table public.asset_characters enable trigger asset_characters_dam_search_refresh_upd;
alter table public.asset_characters enable trigger asset_characters_dam_search_refresh_del;

-- 6. PopDAM usage counters per core character.
create table dam.character_usage (
  core_character_id uuid primary key references core.character (id) on delete cascade,
  usage_count integer not null default 0,
  is_priority boolean not null default false,
  updated_at timestamptz not null default now()
);
comment on table dam.character_usage is
  'PopDAM character usage_count / is_priority keyed by core.character (popcre/shared-db#6995); replaces public.characters columns.';
alter table dam.character_usage enable row level security;
revoke all on dam.character_usage from public, anon, authenticated;
grant select on dam.character_usage to authenticated;
grant all on dam.character_usage to service_role;
create policy character_usage_read on dam.character_usage
  for select to authenticated using (true);

insert into dam.character_usage (core_character_id, usage_count, is_priority)
select m.core_character_id,
       least(sum(coalesce(pc.usage_count, 0)), 2147483647)::integer,
       coalesce(bool_or(pc.is_priority), false)
from dam.character_core_map m
join public.characters pc on pc.id = m.public_character_id
group by m.core_character_id;

-- 7. Search builders: asset_characters now joins core.character.
do $$
declare
  v_fn regprocedure;
  v_old text;
  v_new text;
begin
  foreach v_fn in array array[
    'dam.search_text_embedding_input(text,uuid)'::regprocedure,
    'public.refresh_dam_search_style_group_document(uuid)'::regprocedure,
    'public.refresh_dam_search_asset_document(uuid)'::regprocedure]
  loop
    v_old := pg_get_functiondef(v_fn);
    v_new := replace(replace(v_old,
      'join public.characters pc on pc.id = ac.character_id',
      'join core.character pc on pc.id = ac.character_id'),
      'join public.characters c on c.id=ac.character_id',
      'join core.character c on c.id=ac.character_id');
    if v_new = v_old or v_new like '%public.characters%' then
      raise exception 'C2: % still reads public.characters (definition drifted)', v_fn;
    end if;
    execute v_new;
  end loop;
end $$;

-- 8. Rebuild search documents whose character text changed: assets that lost
--    an unmapped link, or whose core name differs from the PopDAM name.
do $$
declare
  v_assets uuid[];
  v_groups uuid[];
  v_chunk uuid[];
  i integer := 1;
begin
  select coalesce(array_agg(distinct x.asset_id), '{}') into v_assets
  from archive.asset_characters_before_core_character_20261124 x
  left join dam.character_core_map m on m.public_character_id = x.character_id
  left join public.characters pc on pc.id = x.character_id
  left join core.character c on c.id = m.core_character_id
  where m.public_character_id is null
     or lower(btrim(pc.name)) is distinct from lower(btrim(c.name));

  select coalesce(array_agg(distinct a.style_group_id), '{}') into v_groups
  from public.assets a where a.id = any(v_assets) and a.style_group_id is not null;

  while i <= coalesce(cardinality(v_assets), 0) loop
    v_chunk := v_assets[i:i + 499];
    perform public.refresh_dam_search_documents_batch(v_chunk, '{}', 500);
    i := i + 500;
  end loop;
  i := 1;
  while i <= coalesce(cardinality(v_groups), 0) loop
    v_chunk := v_groups[i:i + 499];
    perform public.refresh_dam_search_documents_batch('{}', v_chunk, 500);
    i := i + 500;
  end loop;
end $$;
