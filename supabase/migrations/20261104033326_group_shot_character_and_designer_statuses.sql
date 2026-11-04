-- popdam3#680, owner rulings Nov 3, 2026:
-- "\"group shot\" should itself be a character for tagging purposes"
-- "Eli is a freelancer/illustrator. the others are not and should be inactivated."
do $$
declare
  target record;
  matched_names text[];
  provenance constant jsonb := '{"issue":"u2giants/popdam3#680"}'::jsonb;
begin
  -- Resolve only existing people. Never create inactive placeholder designers.
  -- Tan and Cliff have canonical full names in the original people seed.
  for target in
    select * from (values
      ('Tan', 'tanisha shah'), ('Cliff', 'clifford brown'),
      ('Hana', 'hana'), ('Uta', 'uta'), ('Ira', 'ira')
    ) as people(short_name, canonical_name)
  loop
    select array_agg(distinct normalized_name) into matched_names
    from (
      select normalized_name from core.creative_designer
      union
      select normalized_name from core.technical_designer
    ) as existing_people
    where normalized_name = lower(target.short_name)
       or normalized_name = target.canonical_name
       or split_part(normalized_name, ' ', 1) = target.canonical_name;

    if coalesce(cardinality(matched_names), 0) <> 1 then
      raise exception 'Expected one existing designer identity for %, found %',
        target.short_name, coalesce(cardinality(matched_names), 0);
    end if;

    update core.creative_designer
    set status = 'inactive', metadata = metadata || provenance, updated_at = now()
    where normalized_name = matched_names[1];

    update core.technical_designer
    set status = 'inactive', metadata = metadata || provenance, updated_at = now()
    where normalized_name = matched_names[1];

    if exists (
      select 1 from core.creative_designer
      where normalized_name = matched_names[1] and status <> 'inactive'
      union all
      select 1 from core.technical_designer
      where normalized_name = matched_names[1] and status <> 'inactive'
    ) then
      raise exception 'Designer % not inactivated', target.short_name;
    end if;
  end loop;

  insert into core."character" (id, licensor_id, property_id, code, name, status, metadata)
  values ('90f4dfa8-b4f9-4880-b2f7-e772f5e40ca7', null, null,
    'tagging_label:group_shot', 'Group Shot', 'active',
    provenance || '{"kind":"tagging_label"}'::jsonb)
  on conflict (id) do update
  set licensor_id = excluded.licensor_id, property_id = excluded.property_id,
      code = excluded.code,
      name = excluded.name, status = excluded.status,
      metadata = core."character".metadata || excluded.metadata, updated_at = now();

  insert into core.freelance_designer (name, status, metadata)
  values ('Eli', 'active', provenance)
  on conflict (normalized_name) do update
  set name = excluded.name, status = excluded.status,
      metadata = core.freelance_designer.metadata || excluded.metadata, updated_at = now();

  if not exists (select 1 from core."character"
    where id = '90f4dfa8-b4f9-4880-b2f7-e772f5e40ca7'
      and licensor_id is null and property_id is null
      and code = 'tagging_label:group_shot'
      and name = 'Group Shot' and status = 'active'
      and metadata @> (provenance || '{"kind":"tagging_label"}'::jsonb)) then
    raise exception 'Group Shot character identity missing';
  end if;
  if not exists (select 1 from core.freelance_designer
    where normalized_name = 'eli' and status = 'active' and metadata @> provenance) then
    raise exception 'Eli missing';
  end if;
end $$;
