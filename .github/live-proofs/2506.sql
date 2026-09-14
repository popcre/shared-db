-- Live proof for #2506 (migration 20260911213429, PR #2726). Read-only.
-- Proves on production, by exact match against
-- supabase/migrations/20260911213429_popsg_search_v2_production_performance.sql:
--   1. the migration is in production's ledger;
--   2. the three live-state partial indexes on public.style_guide_files are valid
--      and their full definitions (column and predicate) equal the migration's;
--   3. public.search_style_guide_library_v2 with the migration's 15-argument
--      signature is SECURITY DEFINER, returns jsonb, has exactly the setting
--      search_path=pg_catalog, auth, and its body is byte-identical to the
--      migration's $function$ body (md5 83b8190bca2ff2b7e08a5e87651785b3).
with fn as (
  select p.prosecdef, p.proconfig, pg_get_function_result(p.oid) as result, md5(p.prosrc) as body_md5
  from pg_proc p
  where p.oid = to_regprocedure(
    'public.search_style_guide_library_v2(text,text,text[],text[],text[],text[],text[],text[],text[],text[],timestamptz,timestamptz,text,integer,integer)'
  )
), idx as (
  select c.relname, i.indisvalid, pg_get_indexdef(c.oid) as def
  from pg_index i
  join pg_class c on c.oid = i.indexrelid
  join pg_class t on t.oid = i.indrelid
  join pg_namespace n on n.oid = t.relnamespace
  where n.nspname = 'public' and t.relname = 'style_guide_files'
), expected(relname, def) as (
  values
    ('idx_sgf_live_preview_ids', 'CREATE INDEX idx_sgf_live_preview_ids ON public.style_guide_files USING btree (id) WHERE (is_active AND (thumbnail_url IS NOT NULL))'),
    ('idx_sgf_live_missing_clean_ids', 'CREATE INDEX idx_sgf_live_missing_clean_ids ON public.style_guide_files USING btree (id) WHERE (is_active AND (thumbnail_url IS NULL) AND (thumbnail_error IS NULL))'),
    ('idx_sgf_live_missing_error_ids', 'CREATE INDEX idx_sgf_live_missing_error_ids ON public.style_guide_files USING btree (id) WHERE (is_active AND (thumbnail_url IS NULL) AND (thumbnail_error IS NOT NULL))')
)
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260911213429')
  and (select count(*) from expected e join idx x on x.relname = e.relname and x.def = e.def and x.indisvalid) = 3
  and (select count(*) from fn
       where prosecdef
         and proconfig = array['search_path=pg_catalog, auth']
         and result = 'jsonb'
         and body_md5 = '83b8190bca2ff2b7e08a5e87651785b3') = 1
) as passed
