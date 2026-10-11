-- Read-only post-apply contract. Ordinary nightly crawl acceptance stays on #107.
select to_regprocedure('public.await_style_guide_matview_refresh(uuid)') is not null
   and has_function_privilege('service_role', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
   and not has_function_privilege('authenticated', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
   and exists (select 1 from cron.job where jobname = 'refresh-style-guide-matviews' and active
     and username = 'postgres' and database = current_database()
     and regexp_replace(command, '[[:space:]]', '', 'g') = 'SELECTpublic.refresh_style_guide_matviews();') as passed;
