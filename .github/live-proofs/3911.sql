-- Live proof for #3911 (migration 20261002204050). Read-only.
-- Proves: migration in ledger; the columns and rollup dependencies it relies on
-- exist; both trigger functions exist; on public.assets the row trigger is
-- enabled AFTER UPDATE FOR EACH ROW (tgtype 17) with a WHEN clause and the
-- statement trigger is enabled AFTER UPDATE FOR EACH STATEMENT (tgtype 16),
-- both limited to the style_group_id column and bound to their functions; and
-- no extraction row points at a group other than its asset's current group.
with sg_col as (
  select a.attnum from pg_catalog.pg_attribute a
  where a.attrelid = pg_catalog.to_regclass('public.assets')
    and a.attname = 'style_group_id' and not a.attisdropped
)
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261002204050')
  and exists (select 1 from sg_col)
  and exists (
    select 1 from pg_catalog.pg_attribute a
    where a.attrelid = pg_catalog.to_regclass('dam.pdf_rich_extraction')
      and a.attname = 'style_group_id' and not a.attisdropped
  )
  and pg_catalog.to_regprocedure('public.refresh_style_group_rich_metadata(uuid)') is not null
  and pg_catalog.to_regprocedure('public.refresh_dam_search_style_group_document(uuid)') is not null
  and exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = pg_catalog.to_regclass('public.assets')
      and t.tgname = 'trg_assets_sync_pdf_rich_extraction_group'
      and t.tgenabled = 'O'
      and t.tgtype = 17
      and t.tgqual is not null
      -- int2vector casts to a 0-based array, so compare by length and members
      and array_length(t.tgattr::int2[], 1) = 1
      and (select attnum from sg_col) = all (t.tgattr::int2[])
      and t.tgfoid = pg_catalog.to_regprocedure('dam.sync_pdf_rich_extraction_style_group()')
  )
  and exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = pg_catalog.to_regclass('public.assets')
      and t.tgname = 'trg_assets_rollup_pdf_rich_extraction_groups'
      and t.tgenabled = 'O'
      and t.tgtype = 16
      -- int2vector casts to a 0-based array, so compare by length and members
      and array_length(t.tgattr::int2[], 1) = 1
      and (select attnum from sg_col) = all (t.tgattr::int2[])
      and t.tgfoid = pg_catalog.to_regprocedure('dam.rollup_moved_pdf_rich_extraction_groups()')
  )
  and not exists (
    select 1 from dam.pdf_rich_extraction e
    join public.assets a on a.id = e.asset_id
    where a.style_group_id is distinct from e.style_group_id
  )
) as passed;
