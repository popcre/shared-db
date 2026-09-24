-- Live proof for #3009 (migration 20260917024050). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger;
--   2. both snapshot read models are populated (files and guides summary rows,
--      at least one guide row) and neither anon nor authenticated can read them;
--   3. the pg_cron job refresh-style-guide-library-default-snapshot is active
--      on a five-minute schedule;
--   4. unfiltered public.search_style_guide_library_v2 calls in files and
--      guides mode at p_limit 50, each run twice, return the snapshot totals
--      and every call completes in under 2 seconds (no statement timeout).
-- The calls run under service_role request claims set locally for this
-- read-only transaction only; the body past the authorization check is the
-- same for every role.
with claims as materialized (
  select set_config('request.jwt.claims', '{"role":"service_role"}', true) as c1,
         set_config('request.jwt.claim.role', 'service_role', true) as c2
), calls as materialized (
  select m.mode, m.n, t.t0, t.r, clock_timestamp() as t1
  from claims
  cross join (values ('files', 1), ('guides', 1), ('files', 2), ('guides', 2)) as m(mode, n)
  cross join lateral (
    select clock_timestamp() as t0,
           public.search_style_guide_library_v2(p_result_mode => m.mode, p_limit => 50) as r
  ) t
)
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260917024050')
  and (select count(*) from public.style_guide_library_default_summary) = 2
  and exists (select 1 from public.style_guide_library_default_guides)
  and not has_table_privilege('anon', 'public.style_guide_library_default_summary', 'SELECT')
  and not has_table_privilege('authenticated', 'public.style_guide_library_default_summary', 'SELECT')
  and not has_table_privilege('anon', 'public.style_guide_library_default_guides', 'SELECT')
  and not has_table_privilege('authenticated', 'public.style_guide_library_default_guides', 'SELECT')
  and exists (select 1 from cron.job
               where jobname = 'refresh-style-guide-library-default-snapshot'
                 and schedule = '*/5 * * * *' and active)
  and (select count(*) from calls c
         join public.style_guide_library_default_summary s on s.result_mode = c.mode
        where (c.r ->> 'total')::bigint = s.total
          and jsonb_array_length(c.r -> 'results') between 1 and 50
          and c.t1 - c.t0 < interval '2 seconds') = 4
) as passed
