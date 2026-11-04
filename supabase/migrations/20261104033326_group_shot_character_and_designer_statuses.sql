-- popdam3#680, owner rulings Nov 3, 2026:
-- "\"group shot\" should itself be a character for tagging purposes"
-- "Eli is a freelancer/illustrator. the others are not and should be inactivated."
insert into core."character" (id, licensor_id, code, name, status, metadata)
values ('90f4dfa8-b4f9-4880-b2f7-e772f5e40ca7', null, 'tagging_label:group_shot', 'Group Shot', 'active', '{"issue":"u2giants/popdam3#680","kind":"tagging_label"}'::jsonb)
on conflict (id) do update set name = excluded.name, code = excluded.code, status = excluded.status, metadata = excluded.metadata;

insert into core.freelance_designer (name, status, metadata)
values ('Eli', 'active', '{"issue":"u2giants/popdam3#680"}'::jsonb)
on conflict (normalized_name) do update set name = excluded.name, status = excluded.status, metadata = core.freelance_designer.metadata || excluded.metadata, updated_at = now();

-- No existing roster row carries these names; these are new inactive records by the owner's ruling.
insert into core.creative_designer (name, status, metadata)
select v.name, 'inactive', '{"issue":"u2giants/popdam3#680"}'::jsonb
from unnest(array['Tan','Cliff','Hana','Uta','Ira']) as v(name)
on conflict (normalized_name) do update set status = excluded.status, metadata = core.creative_designer.metadata || excluded.metadata, updated_at = now();

-- No existing roster row carries these names; these are new inactive records by the owner's ruling.
insert into core.technical_designer (name, status, metadata)
select v.name, 'inactive', '{"issue":"u2giants/popdam3#680"}'::jsonb
from unnest(array['Tan','Cliff','Hana','Uta','Ira']) as v(name)
on conflict (normalized_name) do update set status = excluded.status, metadata = core.technical_designer.metadata || excluded.metadata, updated_at = now();

do $$
begin
  if not exists (select 1 from core."character" where id = '90f4dfa8-b4f9-4880-b2f7-e772f5e40ca7' and status = 'active' and name = 'Group Shot' and licensor_id is null) then
    raise exception 'Group Shot character missing';
  end if;
  if (select count(*) from core.creative_designer where normalized_name in ('tan','cliff','hana','uta','ira') and status = 'inactive') <> 5 then
    raise exception 'creative designers not inactivated';
  end if;
  if (select count(*) from core.technical_designer where normalized_name in ('tan','cliff','hana','uta','ira') and status = 'inactive') <> 5 then
    raise exception 'technical designers not inactivated';
  end if;
  if not exists (select 1 from core.freelance_designer where normalized_name = 'eli' and status = 'active') then
    raise exception 'Eli missing';
  end if;
end $$;
