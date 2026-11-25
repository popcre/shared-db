-- Issue #4430 installed-catalog proof, READ ONLY.
WITH wrapped AS (
  select count(*) as n from pg_policies
  where schemaname = 'core' and tablename = 'packaging_type'
    and policyname in ('admin_or_packaging_manager_write','shared_read')
    and qual like '%( SELECT app.has_role(%'
)
select (w.n = 2) as passed from wrapped w;
