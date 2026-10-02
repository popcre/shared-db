-- #3911: spec-sheet extractions follow their asset to its current style group.
--
-- dam.pdf_rich_extraction.style_group_id is stamped only when a PDF is
-- extracted. When an asset changes group (regroup, or group delete/recreate,
-- which first SET NULLs and then sets the new id), the extraction row kept the
-- old id; public.refresh_style_group_rich_metadata rolls up by that column, so
-- the group's spec-sheet data vanished and nothing healed it (2026-10-02: 233
-- rows / 227 groups orphaned).
--
-- This row trigger re-points the asset's extraction row and re-runs the
-- existing rollups. It is a no-op for assets that have no extraction row.

create function dam.sync_pdf_rich_extraction_style_group()
returns trigger
language plpgsql
security definer
set search_path = public, dam
as $$
begin
  if new.style_group_id is not distinct from old.style_group_id then
    return null;
  end if;

  update dam.pdf_rich_extraction e
  set style_group_id = new.style_group_id
  where e.asset_id = new.id
    and e.style_group_id is distinct from new.style_group_id;

  if not found then
    return null;
  end if;

  if old.style_group_id is not null then
    perform public.refresh_style_group_rich_metadata(old.style_group_id);
  end if;
  if new.style_group_id is not null then
    perform public.refresh_style_group_rich_metadata(new.style_group_id);
    perform public.refresh_dam_search_style_group_document(new.style_group_id);
  end if;

  return null;
end;
$$;

revoke all on function dam.sync_pdf_rich_extraction_style_group() from public, anon, authenticated;

create trigger trg_assets_sync_pdf_rich_extraction_group
  after update of style_group_id on public.assets
  for each row
  execute function dam.sync_pdf_rich_extraction_style_group();
