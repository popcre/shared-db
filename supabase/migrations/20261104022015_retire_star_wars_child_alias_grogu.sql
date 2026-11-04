-- popdam3#680, forward correction of 20261104013452 (preserved unchanged).
-- No preview or production ledger state is assumed here.
-- "Child" and "Grogu" are one Star Wars character. Retirement requires an existing row.
create table if not exists archive.character_child_grogu_links_20261104 (
  asset_id uuid primary key,
  old_row jsonb not null,
  archived_at timestamptz not null default now()
);
alter table archive.character_child_grogu_links_20261104 enable row level security;

do $$
declare
  c_child constant uuid := '0e5896e5-7813-4f82-a428-d4669504100a';
  c_grogu constant uuid := '5183540b-1ae9-4eeb-9efc-b638deda17ac';
  v_licensor uuid;
  v_child_licensor uuid;
  v_dependents bigint;
  v_reference record;
begin
  lock table core."character", core.character_alias, public.asset_licensor_characters
    in share row exclusive mode;

  select licensor_id into v_licensor from core."character" where id = c_grogu;
  if not found then
    raise exception 'Grogu must exist';
  end if;
  if v_licensor is null then
    raise exception 'Grogu must have a licensor';
  end if;
  select licensor_id into v_child_licensor from core."character" where id = c_child;
  if not found then
    raise exception 'Child must exist; retirement is not deletion';
  end if;
  if v_child_licensor is distinct from v_licensor then
    raise exception 'Child and Grogu must share one licensor';
  end if;

  -- Discover all incoming foreign-key columns, including source/landing bridges.
  -- Only the asset links moved below are exempt. Lock each table against writes
  -- so a new dependent cannot appear between this check and retirement.
  for v_reference in
    select distinct n.nspname as schema_name, t.relname as table_name,
                    a.attname as column_name
    from pg_catalog.pg_constraint fk
    join pg_catalog.pg_class t on t.oid = fk.conrelid
    join pg_catalog.pg_namespace n on n.oid = t.relnamespace
    cross join lateral unnest(fk.conkey, fk.confkey) as k(local_key, remote_key)
    join pg_catalog.pg_attribute a on a.attrelid = t.oid and a.attnum = k.local_key
    join pg_catalog.pg_attribute target
      on target.attrelid = fk.confrelid and target.attnum = k.remote_key
    where fk.contype = 'f'
      and fk.confrelid = 'core.character'::regclass
      and target.attname = 'id'
      and not (fk.conrelid = 'public.asset_licensor_characters'::regclass
               and a.attname = 'character_id')
    order by schema_name, table_name, column_name
  loop
    execute format('lock table %I.%I in share mode',
                   v_reference.schema_name, v_reference.table_name);
    execute format('select count(*) from %I.%I where %I = $1',
                   v_reference.schema_name, v_reference.table_name, v_reference.column_name)
      into v_dependents using c_child;
    if v_dependents > 0 then
      raise exception 'Child has % dependents in %.%; handle them first',
        v_dependents, v_reference.schema_name, v_reference.table_name;
    end if;
  end loop;

  if exists (
    select 1 from core.character_alias x
    where x.licensor_id = v_licensor
      and x.normalized_alias = core.normalize_popsg_property_observation('Child')
      and x.character_id is distinct from c_grogu
  ) then
    raise exception 'Child alias is already assigned to another character';
  end if;

  insert into archive.character_child_grogu_links_20261104 (asset_id, old_row)
  select l.asset_id, to_jsonb(l)
  from public.asset_licensor_characters l
  where l.character_id = c_child
  on conflict (asset_id) do nothing;

  insert into public.asset_licensor_characters (asset_id, character_id, source, model, tagged_at)
  select l.asset_id, c_grogu, l.source, l.model, l.tagged_at
  from public.asset_licensor_characters l
  where l.character_id = c_child
  on conflict (asset_id, character_id) do nothing;

  delete from public.asset_licensor_characters where character_id = c_child;

  update core."character" set status = 'archived' where id = c_child;

  insert into core.character_alias (character_id, licensor_id, alias, source_system, evidence_notes)
  select c_grogu, v_licensor, 'Child', 'popdam3#680', 'Duplicate name merged into Grogu'
  where not exists (
    select 1 from core.character_alias x
    where x.licensor_id = v_licensor
      and x.normalized_alias = core.normalize_popsg_property_observation('Child')
  );

  if exists (select 1 from public.asset_licensor_characters where character_id = c_child)
     or not exists (select 1 from core."character" where id = c_child and status = 'archived') then
    raise exception 'Child was not retired';
  end if;
end $$;
