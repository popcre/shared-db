-- #4190 (popdam3 #293 DB half): coalesce the style-guide matview refresh cadence.
--
-- Schedule-only change. No function body or materialized view definition changes.
--
-- Measured 2026-10-11 (read-only, production, last 7 days of cron.job_run_details):
--   refresh-style-guide-matviews                  */15  672 runs, avg 14.6 s
--   refresh-style-guide-library-default-snapshot  */5  2016 runs, avg 45.1 s (~25 h DB time/week)
--   style_guide_search_sync_queue is empty (backlog drained by #3458 bounded refresh); the
--   source rows change essentially only during the nightly crawl, whose completion path
--   already refreshes the matviews on demand. The cron jobs stay as the safety net.
--
-- New cadence:
--   refresh-style-guide-matviews                  hourly at :07
--   refresh-style-guide-library-default-snapshot  every 15 minutes
--
-- Idempotent: alters each job by name. A missing job (e.g. a preview branch without the
-- scheduler rows) is reported with a NOTICE and skipped; production proof reads cron.job.

do $cadence$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname = 'refresh-style-guide-matviews';
  if v_job_id is null then
    raise notice 'cron job refresh-style-guide-matviews not found; skipped';
  else
    perform cron.alter_job(job_id := v_job_id, schedule := '7 * * * *');
  end if;

  select jobid into v_job_id from cron.job where jobname = 'refresh-style-guide-library-default-snapshot';
  if v_job_id is null then
    raise notice 'cron job refresh-style-guide-library-default-snapshot not found; skipped';
  else
    perform cron.alter_job(job_id := v_job_id, schedule := '*/15 * * * *');
  end if;
end
$cadence$;
