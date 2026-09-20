-- #2357: invented fixtures only. CI runs this against a throwaway database.
begin;
do $test$
declare
  a uuid; b uuid; root uuid; i integer; n bigint; r record; v text;
begin
  insert into plm.licensing_write_authorization
    (backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
  select pg_backend_pid(),txid_current(),'core.licensor','scrape_consolidation',gen_random_uuid(),
    repeat('1',64),'issue-2357-fixture',array['name','code','status'],clock_timestamp()+interval '1 minute'
    from generate_series(1,2);
  insert into core.licensor(name,code,status) values ('ZZ Fixture 2357 A','ZZ2357A','active') returning id into a;
  insert into core.licensor(name,code,status) values ('ZZ Fixture 2357 B','ZZ2357B','active') returning id into b;
  insert into plm.source_resolution(source_system,entity_kind,source_id,resolution_reason)
    values ('disney_opa','property','923570001','ZZ PRIVATE TEXT 2357'),
           ('paramount','property','923570001','ZZ PRIVATE TEXT 2357');
  insert into plm.licensing_source_scope
    (licensor_id,source_system,source_purpose,scope_axis,permitted_kind,authorized_at,authorized_by)
    values (a,'disney_opa','canonical_identity','entity','property',now(),'ZZ Fixture'),
           (b,'disney_opa','reference_only','entity','property',now(),'ZZ Fixture');
  insert into plm.licensing_relationship_resolution
    (licensor_id,source_system,relationship_kind,source_left_id,source_right_id,evidence_kind,source_evidence,resolution_reason)
    values (a,'disney_opa','property_character','ZZ2357-left','ZZ2357-right','direct_source_assertion','ZZ PRIVATE TEXT 2357','ZZ PRIVATE TEXT 2357'),
           (b,'disney_opa','property_character','ZZ2357-left','ZZ2357-right','direct_source_assertion','ZZ PRIVATE TEXT 2357','ZZ PRIVATE TEXT 2357');

  -- Actual browser reads, not just grants. Original CASE subquery fails here.
  set local role authenticated;
  select * into strict r from api.licensing_entity_candidates where source_system='disney_opa' and source_id='923570001';
  if r.opa_evidence_readable or r.opa_observation_count is not null then raise exception '2357 browser evidence must be unreadable/NULL'; end if;
  if jsonb_array_length(r.source_scope_by_licensor) <> 2 then raise exception '2357 licensor scopes collapsed'; end if;
  if to_jsonb(r)::text like '%ZZ PRIVATE TEXT%' then raise exception '2357 entity free text leaked'; end if;
  select count(*) into n from api.licensing_relationship_candidates where source_left_id='ZZ2357-left';
  if n<>2 then raise exception '2357 cross-licensor candidates collapsed'; end if;
  if exists(select 1 from api.licensing_relationship_candidates where source_left_id='ZZ2357-left' and eligible_for_match) then raise exception '2357 unapproved relationship scope claimed authority'; end if;
  if exists(select 1 from api.licensing_relationship_candidates c where to_jsonb(c)::text like '%ZZ PRIVATE TEXT%') then raise exception '2357 relationship free text leaked'; end if;
  select count(*) into n from api.licensing_resolution_queue where scope_axis='relationship' and licensor_id in (a,b);
  if n<>2 then raise exception '2357 queue lost licensor grain'; end if;
  reset role;
  insert into plm.licensing_source_scope
    (licensor_id,source_system,source_purpose,scope_axis,permitted_kind,authorized_at,authorized_by)
    values (a,'disney_opa','relationship_evidence','relationship','property_character',now(),'ZZ Fixture');
  set local role authenticated;
  select count(*) into n from api.licensing_relationship_candidates where source_left_id='ZZ2357-left' and eligible_for_match;
  if n<>1 then raise exception '2357 one licensors permission leaked to the other'; end if;
  reset role;
  set local role anon;
  foreach v in array array['api.licensing_entity_candidates','api.licensing_relationship_candidates','api.licensing_resolution_queue'] loop
    begin
      execute format('select count(*) from %s',v);
      raise exception '2357 anonymous read unexpectedly succeeded';
    exception when insufficient_privilege then null;
    end;
  end loop;
  begin
    perform * from plm.licensing_opa_observation_count('disney_opa','property','923570001');
    raise exception '2357 anonymous helper unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- Two complete roots plus a newer incomplete root, each with the same identity.
  for i in 1..3 loop
    insert into plm.opa_capture(capture_key,source_repository,source_commit_sha,source_manifest_sha256,
      source_captured_at,load_completed_at,status,expected_scope_count,expected_unique_property_count,
      expected_unique_character_count,expected_scope_membership_count,expected_cross_scope_property_count,
      expected_relationship_count,created_by)
    values ('ZZ2357-root-'||i,'fixture',repeat('1',40),repeat('2',64),timestamptz '2199-01-01Z'+i*interval '1 day',
      case when i<3 then now() end,case when i<3 then 'complete' else 'loading' end,2,1,1,1,0,1,'ZZ Fixture') returning id into root;
    insert into plm.opa_capture_scope(capture_id,scope_key,region,branch,lob,submission_type,template_id,workflow_id,
      source_sha256,expected_property_count,expected_character_count,expected_relationship_count,expected_relationship_sha256)
    values(root,'disney_home_standard','North America','Disney','200','Standard','21','49',repeat('1',64),1,1,1,repeat('1',64));
    insert into plm.opa_property_character_capture(capture_id,scope_key,chunk_key,chunk_sha256,licensed_property_id,
      property_name,option_source_id,character_id,character_name,brand_property_id,source_row_sha256)
    select root,'disney_home_standard','ZZ2357',repeat('1',64),923570001,'ZZ PRIVATE TEXT 2357',1,j,'ZZ Character',1,repeat('2',64)
      from generate_series(1,i) j;
  end loop;
  set local role service_role;
  select * into strict r from api.licensing_entity_candidates where source_system='disney_opa' and source_id='923570001';
  if not r.opa_evidence_readable or r.opa_observation_count<>2 then raise exception '2357 latest complete root expected 2, got %',r.opa_observation_count; end if;
  select * into strict r from api.licensing_entity_candidates where source_system='paramount' and source_id='923570001';
  if r.opa_evidence_readable or r.opa_observation_count is not null then raise exception '2357 non-OPA evidence must be NULL'; end if;
  select * into strict r from plm.licensing_opa_observation_count('disney_opa','property',repeat('9',100));
  if r.evidence_readable or r.observation_count is not null then raise exception '2357 overflowing source ID must abstain'; end if;
  select * into strict r from plm.licensing_opa_observation_count('disney_opa','property','923579999');
  if not r.evidence_readable or r.observation_count<>0 then raise exception '2357 valid readable absence must be zero'; end if;
  perform count(*) from api.licensing_relationship_candidates;
  perform count(*) from api.licensing_resolution_queue;
  reset role;

  create policy issue2357_fixture_restrict on plm.source_resolution
    as restrictive for select to authenticated using(source_id<>'923570001');
  set local role authenticated;
  select count(*) into n from api.licensing_entity_candidates where source_id='923570001';
  if n<>0 then raise exception '2357 entity view bypassed caller RLS'; end if;
  reset role;
  drop policy issue2357_fixture_restrict on plm.source_resolution;

  -- Grant alone is not data visibility: actual underlying RLS still governs helper.
  grant select on plm.opa_capture,plm.opa_property_character_capture to authenticated;
  set local role authenticated;
  select * into strict r from plm.licensing_opa_observation_count('disney_opa','property','923570001');
  if r.evidence_readable or r.observation_count is not null then raise exception '2357 helper bypassed root RLS'; end if;
  reset role;
  create policy issue2357_fixture_root on plm.opa_capture for select to authenticated using(true);
  set local role authenticated;
  select * into strict r from plm.licensing_opa_observation_count('disney_opa','property','923570001');
  if r.evidence_readable or r.observation_count is not null then raise exception '2357 filtered evidence misreported a complete zero'; end if;
  reset role;
  drop policy issue2357_fixture_root on plm.opa_capture;
  revoke select on plm.opa_capture,plm.opa_property_character_capture from authenticated;
end
$test$;
rollback;
