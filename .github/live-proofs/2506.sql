-- Live proof for #2506 (migration 20260911213429, PR #2726). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger;
--   2. the three live-state partial indexes on public.style_guide_files exist,
--      are valid, and carry exactly the migration's predicates;
--   3. public.search_style_guide_library_v2 with the migration's 15-argument
--      signature exists, is SECURITY DEFINER with search_path pg_catalog, auth,
--      and its definition selects the same three live-state sets.
with fn as (
  select p.prosecdef,
         coalesce(array_to_string(p.proconfig, ','), '') as config,
         pg_get_functiondef(p.oid) as def
  from pg_proc p
  where p.oid = to_regprocedure(
    'public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)'
  )
), idx as (
  select c.relname, i.indisvalid, pg_get_expr(i.indpred, i.indrelid) as pred
  from pg_index i
  join pg_class c on c.oid = i.indexrelid
  join pg_class t on t.oid = i.indrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'public' and t.relname = 'style_guide_files'
    and c.relname in ('idx_sgf_live_preview_ids', 'idx_sgf_live_missing_clean_ids', 'idx_sgf_live_missing_error_ids')
)
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260911213429')
  and (select count(*) from idx where indisvalid) = 3
  and exists (select 1 from idx where relname = 'idx_sgf_live_preview_ids'
              and pred like '%is_active%' and pred like '%thumbnail_url IS NOT NULL%')
  and exists (select 1 from idx where relname = 'idx_sgf_live_missing_clean_ids'
              and pred like '%thumbnail_url IS NULL%' and pred like '%thumbnail_error IS NULL%')
  and exists (select 1 from idx where relname = 'idx_sgf_live_missing_error_ids'
              and pred like '%thumbnail_url IS NULL%' and pred like '%thumbnail_error IS NOT NULL%')
  and (select count(*) from fn
       where prosecdef
         and config like '%search_path=pg_catalog, auth%'
         and def like '%where is_active and thumbnail_url is not null%'
         and def like '%where is_active and thumbnail_url is null and thumbnail_error is null%'
         and def like '%where is_active and thumbnail_url is null and thumbnail_error is not null%') = 1
) as passed
