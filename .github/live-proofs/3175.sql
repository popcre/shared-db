-- #3175: bind tested bodies and unchanged ACLs to their production installation.
-- Detectors write observations, so NEVER call them in this read-only proof.
with expected(signature, body_md5) as (values
    ('plm.check_taxonomy_sync_health(interval,jsonb)', '8017089a3117e9ebb5a339869848abfe'),
    ('plm.record_taxonomy_parallel_observation(date,jsonb)', '9eda037f91491877d776412043538a12')
), installed as (
  select e.*, p.oid, p.prosrc, p.prosecdef
  from expected e left join pg_proc p on p.oid=to_regprocedure(e.signature)
)
select (
  exists(select 1 from supabase_migrations.schema_migrations where version='20260920151128')
  and count(*)=2
  and bool_and(oid is not null and md5(prosrc)=body_md5 and prosecdef
      and not has_function_privilege('anon',oid,'EXECUTE')
      and not has_function_privilege('authenticated',oid,'EXECUTE')
      and has_function_privilege('service_role',oid,'EXECUTE'))
) as passed from installed
