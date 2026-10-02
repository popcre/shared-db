-- #3911: spec-sheet extractions follow their asset to its current style group.
--
-- dam.pdf_rich_extraction.style_group_id is stamped only when a PDF is
-- extracted. When an asset changes group (regroup, or a public.style_groups
-- delete, whose FK on public.assets.style_group_id is ON DELETE SET NULL,
-- followed by re-assignment to a recreated group) the extraction row kept the
-- old id. public.refresh_style_group_rich_metadata rolls up by that column, so
-- the group's spec-sheet data vanished and nothing healed it (2026-10-02: 233
-- rows / 227 groups orphaned).
--
-- Design (review of PR #3913): a STATEMENT-level AFTER UPDATE trigger with
-- transition tables, so a bulk regroup costs one hash join of the changed rows
-- against dam.pdf_rich_extraction (~250 rows) per statement, and each affected
-- group is rolled up exactly once per statement, never once per asset.
-- (PostgreSQL forbids a column list together with transition tables, so the
-- trigger is UPDATE-wide; the existing trg_refresh_sg_counts_on_update on
-- public.assets already uses the same transition-table shape.)
--
-- Rollback: drop trigger trg_assets_sync_pdf_rich_extraction_group on
-- public.assets; drop function dam.sync_pdf_rich_extraction_style_group();
-- No data is changed by this migration itself.

create function dam.sync_pdf_rich_extraction_style_group()
returns trigger
language plpgsql
security definer
set search_path = public, dam, pg_temp
as $$
declare
  v_gids uuid[];
  v_gid uuid;
begin
  with moved as (
    select n.id as asset_id, o.style_group_id as old_gid, n.style_group_id as new_gid
    from new_assets n
    join old_assets o on o.id = n.id
    where n.style_group_id is distinct from o.style_group_id
  ),
  repointed as (
    update dam.pdf_rich_extraction e
    set style_group_id = m.new_gid
    from moved m
    where e.asset_id = m.asset_id
      and e.style_group_id is distinct from m.new_gid
    returning m.old_gid, m.new_gid
  )
  select array_agg(distinct g)
  into v_gids
  from repointed r, lateral unnest(array[r.old_gid, r.new_gid]) g
  where g is not null;

  foreach v_gid in array coalesce(v_gids, '{}'::uuid[]) loop
    perform public.refresh_style_group_rich_metadata(v_gid);
    perform public.refresh_dam_search_style_group_document(v_gid);
  end loop;

  return null;
end;
$$;

comment on function dam.sync_pdf_rich_extraction_style_group() is
  '#3911: statement-level trigger on public.assets; re-points dam.pdf_rich_extraction.style_group_id to the asset''s current group and re-runs the rich-metadata and search rollups once per affected group.';

revoke all on function dam.sync_pdf_rich_extraction_style_group() from public, anon, authenticated;

create trigger trg_assets_sync_pdf_rich_extraction_group
  after update on public.assets
  referencing old table as old_assets new table as new_assets
  for each statement
  execute function dam.sync_pdf_rich_extraction_style_group();
