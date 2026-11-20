-- popcre/shared-db#3458 (u2giants/popdam3#107): after 20261222090000 fixed the
-- reconcile preview count, the 2026-11-19 nightly crawl (run 914aa546) still
-- failed with "canceling statement due to statement timeout", now inside
-- reconcile_stale_sg_files_batch line 137: the deactivation UPDATE of the FIRST
-- 500-row batch (postgres log 2026-11-20 02:17:24 UTC). Every deactivated file
-- is a non-HOT update of style_guide_files (three trigram GIN indexes, four row
-- triggers) and of style_guide_search_documents (801 MB HNSW index, GIN
-- search_vector), right after an ingest rewrote ~223k rows. The counts now take
-- 0.2 s, so the write batch is what exceeds the 8 s ceiling. The per-call cap is
-- cut from 500 to 50 rows; callers already loop on done=false, so a run only
-- makes more, smaller calls. Function body only; grants are unchanged.
-- derived-from: 20261111132448
begin;
set local lock_timeout='2s';
set local statement_timeout='60s';
set local search_path=pg_catalog,public;

do $migrate$
declare
  v_def text;
begin
  if not exists (
    select 1 from pg_proc p
     where p.oid = to_regprocedure('public.reconcile_stale_sg_files_batch(text,uuid,integer,numeric)')
       and md5(p.prosrc) = 'e83ac0cbc1c53e5710930932d1125b2a') then
    raise exception 'reconcile_stale_sg_files_batch source differs from 20261111132448; reconcile rather than overwrite';
  end if;
  v_def := pg_get_functiondef('public.reconcile_stale_sg_files_batch(text,uuid,integer,numeric)'::regprocedure);
  if (length(v_def) - length(replace(v_def, 'least(coalesce(p_batch_size, 500), 500)', ''))) <> length('least(coalesce(p_batch_size, 500), 500)') then
    raise exception 'expected exactly one 500-row cap in reconcile_stale_sg_files_batch';
  end if;
  v_def := replace(v_def, 'least(coalesce(p_batch_size, 500), 500)', 'least(coalesce(p_batch_size, 50), 50)');
  v_def := replace(v_def, '-- #2792: at most 500 rows are written per call',
                          '-- #2792/#3458: at most 50 rows are written per call');
  execute v_def;
end;
$migrate$;

commit;
