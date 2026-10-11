-- Issue #3458; claim #4200. PopDAM #335: await the existing successful
-- scheduler refresh instead of running a full concurrent refresh in an 8s RPC.
-- derived-from: none
-- No scheduler, timeout, matview, source data, or legacy RPC is changed.
create or replace function public.await_style_guide_matview_refresh(p_run_id uuid)
returns table (ready boolean, refreshed_at timestamptz)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_start timestamptz;
  v_ingest timestamptz;
  v_state text;
  v_job bigint;
  v_finished timestamptz;
begin
  if p_run_id is null then
    raise exception 'A crawl run is required';
  end if;
  select r.refresh_started_at, r.ingest_completed_at, r.lifecycle_state
    into v_start, v_ingest, v_state
    from public.style_guide_crawl_runs r where r.id = p_run_id for update;
  if not found or v_ingest is null or v_state not in ('reconciling', 'refreshing') then
    raise exception 'Crawl must have finished ingestion and reconciliation before awaiting refresh';
  end if;
  select j.jobid into v_job from cron.job j
   where j.jobname = 'refresh-style-guide-matviews' and j.active
     and j.username = 'postgres' and j.database = current_database()
     and regexp_replace(j.command, '[[:space:]]', '', 'g') = 'SELECTpublic.refresh_style_guide_matviews();';
  if v_job is null then
    raise exception 'The existing PopSG refresh scheduler is unavailable or its command changed';
  end if;
  if v_start is null then
    v_start := clock_timestamp();
    update public.style_guide_crawl_runs
       set refresh_started_at = v_start, lifecycle_state = 'refreshing'
     where id = p_run_id;
  end if;
  -- A refresh started before this crawl entered refresh is never evidence.
  -- Completion of a cron run proves both matviews refreshed successfully.
  select max(d.end_time) into v_finished from cron.job_run_details d
   where d.jobid = v_job and d.status = 'succeeded'
     and d.start_time >= greatest(v_start, v_ingest)
     and d.end_time >= d.start_time;
  if v_finished is null and clock_timestamp() - v_start > interval '20 minutes' then
    raise exception 'No successful scheduled PopSG refresh within 20 minutes';
  end if;
  -- Never stamp refresh_completed_at here: the existing search-only step must
  -- drain search synchronization before the caller can complete the crawl.
  return query select v_finished is not null, v_finished;
end;
$function$;
comment on function public.await_style_guide_matview_refresh(uuid) is
  'Issue #3458 / PopDAM #335. Service-only bounded wait for successful existing cron refresh begun after crawl refresh_started_at. ready=false means retry (30s); ready=true allows the existing search-only RPC. Never marks a crawl complete, changes scheduler configuration, or refreshes in the API request.';
revoke all on function public.await_style_guide_matview_refresh(uuid) from public, anon, authenticated;
grant execute on function public.await_style_guide_matview_refresh(uuid) to service_role;

do $verify$
begin
  if not has_function_privilege('service_role', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
     or has_function_privilege('anon', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.await_style_guide_matview_refresh(uuid)', 'execute') then
    raise exception 'PopSG scheduled refresh wait privileges are incorrect';
  end if;
end
$verify$;

notify pgrst, 'reload schema';
