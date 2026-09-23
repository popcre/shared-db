-- #2357 production shape/security proof; role-executed positive and negative
-- behavior lives in the ephemeral licensing_candidate_and_review_apis contract.
-- Every array/nullable test is coalesced so a NULL can never read as a pass.
with views as (
  select c.oid,c.relkind,c.reloptions,c.relacl,c.relowner
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='api' and c.relname in
    ('licensing_entity_candidates','licensing_relationship_candidates','licensing_resolution_queue')
), helper as (
  select p.* from pg_proc p where p.oid=to_regprocedure('plm.licensing_opa_observation_count()')
), required(view_name,col) as (values
  ('licensing_entity_candidates','source_id'),('licensing_entity_candidates','needs_decision'),
  ('licensing_entity_candidates','is_ambiguous'),('licensing_entity_candidates','source_scope_by_licensor'),
  ('licensing_entity_candidates','opa_evidence_readable'),('licensing_entity_candidates','opa_observation_count'),
  ('licensing_relationship_candidates','licensor_id'),('licensing_relationship_candidates','evidence_kind'),
  ('licensing_relationship_candidates','needs_decision'),('licensing_relationship_candidates','is_ambiguous'),
  ('licensing_relationship_candidates','eligible_for_match'),('licensing_relationship_candidates','scope_row_count'),
  ('licensing_relationship_candidates','relationship_evidence_permitted'),('licensing_relationship_candidates','source_purposes'),
  ('licensing_resolution_queue','scope_axis'),('licensing_resolution_queue','licensor_id'),
  ('licensing_resolution_queue','item_kind'),('licensing_resolution_queue','resolution_status'),
  ('licensing_resolution_queue','item_count'),('licensing_resolution_queue','is_ambiguous'),
  ('licensing_resolution_queue','oldest_created_at')
), deps(view_name,base) as (values
  ('api.licensing_entity_candidates','plm.source_resolution'),
  ('api.licensing_entity_candidates','plm.licensing_source_scope'),
  ('api.licensing_relationship_candidates','plm.licensing_relationship_resolution'),
  ('api.licensing_relationship_candidates','plm.licensing_source_scope'),
  ('api.licensing_resolution_queue','plm.source_resolution'),
  ('api.licensing_resolution_queue','plm.licensing_relationship_resolution')
)
select coalesce((
  (select count(*)=3 and coalesce(bool_and(relkind='v'
    and 'security_invoker=true'=any(coalesce(reloptions,'{}'))
    and has_table_privilege('authenticated',oid,'SELECT')
    and has_table_privilege('service_role',oid,'SELECT')
    and not has_table_privilege('anon',oid,'SELECT')),false) from views)
  and not exists(select 1 from views v,lateral aclexplode(coalesce(v.relacl,acldefault('r',v.relowner))) a
    where a.grantee=0 and a.privilege_type='SELECT')
  and (select count(*)=1 and coalesce(bool_and(not prosecdef and provolatile='s' and proparallel='s' and proretset
    and prolang=(select oid from pg_language where lanname='plpgsql')
    and 'search_path=""'=any(coalesce(proconfig,'{}'))
    and pg_get_function_result(oid)='TABLE(evidence_readable boolean, licensed_property_id bigint, observation_count bigint)'
    and has_function_privilege('authenticated',oid,'EXECUTE')
    and has_function_privilege('service_role',oid,'EXECUTE')
    and not has_function_privilege('anon',oid,'EXECUTE')),false) from helper)
  and not exists(select 1 from required r where not exists(select 1 from pg_attribute a
    where a.attrelid=to_regclass('api.'||r.view_name) and a.attname=r.col and a.attnum>0 and not a.attisdropped))
  and not exists(select 1 from deps d where not exists(select 1 from pg_rewrite rw join pg_depend dep
    on dep.classid='pg_rewrite'::regclass and dep.objid=rw.oid
    where rw.ev_class=to_regclass(d.view_name) and dep.refclassid='pg_class'::regclass
      and dep.refobjid=to_regclass(d.base)))
  and not exists(select 1 from pg_attribute where attrelid in (select oid from views)
    and not attisdropped and attname in (
      'property_name','character_name','licensed_property_id','brand_property_id',
      'option_source_id','source_row_sha256','chunk_sha256','source_manifest_sha256',
      'source_commit_sha','capture_key','created_by','source_evidence','resolution_reason'))
),false) as passed;
