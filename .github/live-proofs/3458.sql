-- Read-only post-apply contract. Ordinary nightly crawl acceptance stays on #107.
select to_regprocedure('public.await_style_guide_matview_refresh(uuid)') is not null
   and has_function_privilege('service_role', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
   and not has_function_privilege('public', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
   and not has_function_privilege('authenticated', 'public.await_style_guide_matview_refresh(uuid)', 'execute')
   and exists (select 1 from cron.job where jobname = 'refresh-style-guide-matviews' and active
     and schedule in ('*/15 * * * *', '7 * * * *')
     and username = 'postgres' and database = current_database()
     and regexp_replace(lower(regexp_replace(command, '[[:space:]]', '', 'g')), chr(59) || '$', '') = 'selectpublic.refresh_style_guide_matviews()')
   and to_regprocedure('public.refresh_style_guide_matviews()') is null
   and exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.refresh_style_guide_matviews(uuid,integer)')
     and p.prosecdef and p.pronargdefaults = 2 and md5(p.prosrc) = '044a40244377bb9b64dc65efbc7ccf6a') as passed;
