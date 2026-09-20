-- #2357 production shape/security proof; role-executed positive and negative
-- behavior lives in the ephemeral licensing_candidate_and_review_apis contract.
with views as (
  select c.oid,c.relkind,c.reloptions,c.relacl,c.relowner
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='api' and c.relname in
    ('licensing_entity_candidates','licensing_relationship_candidates','licensing_resolution_queue')
), helper as (
  select p.* from pg_proc p where p.oid=to_regprocedure('plm.licensing_opa_observation_count(text,text,text)')
)
select (
  (select count(*)=3 and bool_and(relkind='v' and 'security_invoker=true'=any(reloptions)
    and has_table_privilege('authenticated',oid,'SELECT')
    and has_table_privilege('service_role',oid,'SELECT')
    and not has_table_privilege('anon',oid,'SELECT')) from views)
  and not exists(select 1 from views v,lateral aclexplode(coalesce(v.relacl,acldefault('r',v.relowner))) a
    where a.grantee=0 and a.privilege_type='SELECT')
  and (select count(*)=1 and bool_and(not prosecdef and provolatile='s'
    and has_function_privilege('authenticated',oid,'EXECUTE')
    and has_function_privilege('service_role',oid,'EXECUTE')
    and not has_function_privilege('anon',oid,'EXECUTE')) from helper)
  and exists(select 1 from pg_attribute where attrelid=to_regclass('api.licensing_resolution_queue')
    and attname='licensor_id' and not attisdropped)
  and exists(select 1 from pg_attribute where attrelid=to_regclass('api.licensing_entity_candidates')
    and attname='source_scope_by_licensor' and not attisdropped)
  and not exists(select 1 from pg_attribute where attrelid in (select oid from views)
    and not attisdropped and attname in ('source_evidence','resolution_reason','property_name','character_name','capture_key'))
) as passed;
