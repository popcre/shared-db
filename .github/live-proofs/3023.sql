-- Live proof for #3023 (migration 20260916232205). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger, and the queue table (RLS on,
--      hidden from API roles), its trigger, and the refresh function body
--      byte-identical to the migration are live;
--   2. the most recent nightly PopSG crawl started after the change and finished
--      completed, with its aggregate refresh recorded.
with fixed as (select timestamptz '2026-09-17 00:00:00+00' as since)
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260916232205')
  and exists (select 1 from pg_class c where c.oid = to_regclass('public.style_guide_search_sync_queue')
              and c.relrowsecurity
              and not has_table_privilege('authenticated', c.oid, 'SELECT')
              and not has_table_privilege('anon', c.oid, 'SELECT'))
  and exists (select 1 from pg_trigger t where t.tgrelid = to_regclass('public.style_guide_files')
              and t.tgname = 'trg_style_guide_files_queue_search_sync' and t.tgenabled = 'O')
  and exists (select 1 from pg_proc p
              where p.oid = to_regprocedure('public.refresh_style_guide_matviews(uuid,integer)')
                and md5(p.prosrc) = '52b676f90e4500dc323c2f9e6e6f3c97')
  and exists (select 1
                from (select r.* from public.style_guide_crawl_runs r
                       order by r.started_at desc limit 1) latest, fixed
               where latest.started_at >= fixed.since
                 and latest.status = 'completed'
                 and latest.lifecycle_state = 'completed'
                 and latest.refresh_completed_at is not null)
) as passed
