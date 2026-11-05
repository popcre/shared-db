-- Three consecutive scheduled nights must actually complete under 60 seconds.
-- Busy invocations raise 55P03, so a skipped night cannot masquerade as success.
with recent as (
  select d.status, d.start_time, d.end_time,
    row_number() over (order by d.start_time desc) as rn
  from cron.job_run_details d join cron.job j on j.jobid=d.jobid
  where j.jobname='resolve-sku-style-guide-links-nightly'
), nights as (
  select * from recent where rn<=3
)
select
  (select count(*)=3 and bool_and(status='succeeded'
      and end_time is not null and end_time-start_time<interval '60 seconds')
      and count(distinct (start_time at time zone 'UTC')::date)=3
      and max((start_time at time zone 'UTC')::date)-min((start_time at time zone 'UTC')::date)=2
    from nights)
  and not exists(select 1 from cron.job where jobname='sku-style-guide-links-catchup-5608')
  and exists(select 1 from public.sku_style_guide_resolver_progress where cardinality(active_link_ids)>0)
  and (select max(last_seen_at) from public.sku_style_guide_links)>=
      (select max(start_time) from nights)
  and not has_function_privilege('authenticated','public.resolve_sku_style_guide_links()','EXECUTE')
  and not has_function_privilege('anon','public.resolve_sku_style_guide_links()','EXECUTE')
  as passed;
