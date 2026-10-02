-- Live proof for #3911 (migration 20261002194321). Read-only.
-- Proves: migration in ledger; trigger function and enabled trigger exist on
-- public.assets; no parsed extraction row points at a group other than its
-- asset's current group.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20261002194321')
  and pg_catalog.to_regprocedure('dam.sync_pdf_rich_extraction_style_group()') is not null
  and exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = pg_catalog.to_regclass('public.assets')
      and t.tgname = 'trg_assets_sync_pdf_rich_extraction_group'
      and t.tgenabled = 'O'
      and t.tgfoid = pg_catalog.to_regprocedure('dam.sync_pdf_rich_extraction_style_group()')
  )
  and not exists (
    select 1 from dam.pdf_rich_extraction e
    join public.assets a on a.id = e.asset_id
    where a.style_group_id is distinct from e.style_group_id
  )
) as passed;
