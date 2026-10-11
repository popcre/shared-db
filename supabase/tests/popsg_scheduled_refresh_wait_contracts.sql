-- #3458/#335: fixture-only behavior tests, rolled back. No full refresh runs.
begin;
do $test$
declare
  v_run uuid;
  v_expired uuid;
  v_job bigint;
  v_ready boolean;
  v_stamp timestamptz;
  v_start timestamptz;
  v_original_command text;
  v_failed boolean;
begin
  select jobid, command into v_job, v_original_command from cron.job
   where jobname = 'refresh-style-guide-matviews';
  if v_job is null then
    v_job := cron.schedule('refresh-style-guide-matviews', '*/15 * * * *', ' SELECT public.refresh_style_guide_matviews(); ');
    v_original_command := ' SELECT public.refresh_style_guide_matviews(); ';
  end if;
  -- Isolate scheduler evidence only inside this rolled-back disposable test.
  delete from cron.job_run_details where jobid = v_job;
  update cron.job set active = true, username = 'postgres', database = current_database(),
    command = ' SELECT public.refresh_style_guide_matviews(); ' where jobid = v_job;
  insert into public.style_guide_crawl_runs (status, lifecycle_state, ingest_completed_at)
    values ('running', 'reconciling', clock_timestamp() - interval '1 minute') returning id into v_run;
  select ready, refreshed_at into v_ready, v_stamp from public.await_style_guide_matview_refresh(v_run);
  if v_ready or v_stamp is not null then raise exception 'Pending scheduler was falsely accepted'; end if;
  select refresh_started_at into v_start from public.style_guide_crawl_runs where id = v_run;
  if v_start is null then raise exception 'Wait boundary was not persisted'; end if;
  insert into cron.job_run_details (jobid, runid, status, start_time, end_time)
    values (v_job, nextval('cron.runid_seq'), 'succeeded', v_start - interval '1 second', v_start + interval '1 second');
  select ready into v_ready from public.await_style_guide_matview_refresh(v_run);
  if v_ready then raise exception 'Refresh begun before reconciliation was accepted'; end if;
  insert into cron.job_run_details (jobid, runid, status, start_time, end_time)
    values (v_job, nextval('cron.runid_seq'), 'failed', v_start, clock_timestamp());
  select ready into v_ready from public.await_style_guide_matview_refresh(v_run);
  if v_ready then raise exception 'Failed scheduler was accepted'; end if;
  if (select refresh_started_at from public.style_guide_crawl_runs where id = v_run) <> v_start then
    raise exception 'Continuation reset the wait boundary';
  end if;
  insert into public.style_guide_crawl_runs (status, lifecycle_state, ingest_completed_at, refresh_started_at)
    values ('running', 'refreshing', clock_timestamp() - interval '22 minutes', clock_timestamp() - interval '21 minutes') returning id into v_expired;
  -- Remove the deliberately old-success fixture, which would be valid for the expired run.
  delete from cron.job_run_details where jobid = v_job and status = 'succeeded';
  v_failed := false;
  begin perform public.await_style_guide_matview_refresh(v_expired);
  exception when raise_exception then v_failed := sqlerrm = 'No successful scheduled PopSG refresh within 20 minutes'; end;
  if not v_failed then raise exception 'An expired wait did not fail'; end if;
  insert into cron.job_run_details (jobid, runid, status, start_time, end_time)
    values (v_job, nextval('cron.runid_seq'), 'succeeded', v_start, clock_timestamp());
  select ready, refreshed_at into v_ready, v_stamp from public.await_style_guide_matview_refresh(v_run);
  if not v_ready or v_stamp is null then raise exception 'Fresh successful refresh was not accepted'; end if;
  if (select refresh_completed_at is not null from public.style_guide_crawl_runs where id = v_run) then
    raise exception 'Search synchronization was skipped by prematurely stamping completion';
  end if;
  update cron.job set active = false where jobid = v_job;
  v_failed := false;
  begin perform public.await_style_guide_matview_refresh(v_run);
  exception when raise_exception then v_failed := true; end;
  if not v_failed then raise exception 'Inactive scheduler was accepted'; end if;
  update cron.job set active = true, command = 'select 1' where jobid = v_job;
  v_failed := false;
  begin perform public.await_style_guide_matview_refresh(v_run);
  exception when raise_exception then v_failed := true; end;
  if not v_failed then raise exception 'Changed scheduler command was accepted'; end if;
  v_failed := false;
  begin perform public.await_style_guide_matview_refresh(null);
  exception when raise_exception then v_failed := true; end;
  if not v_failed then raise exception 'Missing run was accepted'; end if;
  if has_function_privilege('anon', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.await_style_guide_matview_refresh(uuid)', 'execute') then
    raise exception 'Service-only privilege contract failed';
  end if;
end
$test$;
rollback;
