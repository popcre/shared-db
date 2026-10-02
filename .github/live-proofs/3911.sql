-- Live proof for #3911 (migration 20261002194321). Read-only.
-- Proves: migration in ledger; the rollup dependencies exist with their (uuid)
-- signatures; the trigger function exists; the trigger on public.assets is
-- enabled, AFTER UPDATE FOR EACH STATEMENT (tgtype 16) with the old_assets /
-- new_assets transition tables, bound to that function; and no extraction row
-- points at a group other than its asset's current group.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261002194321')
  and pg_catalog.to_regprocedure('public.refresh_style_group_rich_metadata(uuid)') is not null
  and pg_catalog.to_regprocedure('public.refresh_dam_search_style_group_document(uuid)') is not null
  and pg_catalog.to_regprocedure('dam.sync_pdf_rich_extraction_style_group()') is not null
  and exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = pg_catalog.to_regclass('public.assets')
      and t.tgname = 'trg_assets_sync_pdf_rich_extraction_group'
      and t.tgenabled = 'O'
      and t.tgtype = 16
      and t.tgoldtable = 'old_assets'
      and t.tgnewtable = 'new_assets'
      and t.tgfoid = pg_catalog.to_regprocedure('dam.sync_pdf_rich_extraction_style_group()')
  )
  and not exists (
    select 1 from dam.pdf_rich_extraction e
    join public.assets a on a.id = e.asset_id
    where a.style_group_id is distinct from e.style_group_id
  )
) as passed;
