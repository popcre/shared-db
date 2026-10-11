-- Issue #2336 contract: hash-pinned licensing consolidation engine.
--
-- Behaviour covers real native NBCU/Paramount/OPA source qualification, physical
-- provenance/support, protected spelling/old aliases, exact retry and conditional
-- support inverse. Current landing constraints and immutable guards remain intact.
-- Catalog assertions complement those row-level regressions.

begin;

do $contracts$
declare
  v_plan plm.licensing_consolidation_plan%rowtype;
  v_plan2 plm.licensing_consolidation_plan%rowtype;
  v_plan_first_id uuid;
  v_plan_first_hash text;
  v_applied plm.licensing_consolidation_plan%rowtype;
  v_count integer;
  v_bool boolean;
  v_text text;
  v_sqlstate text;
  v_capture uuid := gen_random_uuid();
  v_capture2 uuid := gen_random_uuid();
  v_licensor uuid;
  v_property uuid;
  v_auth_id uuid;
  t text;
begin
  -- ---------------------------------------------------------------------------------
  -- Shape: the plan table exists and is EMPTY. #2336 authorizes no plan rows, so a
  -- populated table here means data reached a public repository or an unauthorized
  -- load ran.
  -- ---------------------------------------------------------------------------------
  if to_regclass('plm.licensing_consolidation_plan') is null then
    raise exception 'CONTRACT: plm.licensing_consolidation_plan does not exist';
  end if;
  select count(*) into v_count from plm.licensing_consolidation_plan;
  if v_count <> 0 then
    raise exception 'CONTRACT: plm.licensing_consolidation_plan must ship empty, found % row(s)', v_count;
  end if;

  -- Fail closed: no client role may write the plan table.
  if has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'insert')
     or has_table_privilege('service_role', to_regclass('plm.licensing_consolidation_plan'), 'insert')
     or has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'update')
     or has_table_privilege('service_role', to_regclass('plm.licensing_consolidation_plan'), 'delete') then
    raise exception 'CONTRACT: plm.licensing_consolidation_plan must have no write grant for any client role';
  end if;
  if not has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'select') then
    raise exception 'CONTRACT: authenticated must be able to read plm.licensing_consolidation_plan';
  end if;
  if has_table_privilege('anon', to_regclass('plm.licensing_consolidation_plan'), 'select') then
    raise exception 'CONTRACT: anon must not be able to read plm.licensing_consolidation_plan';
  end if;

  -- RLS on.
  select c.relrowsecurity into v_bool
    from pg_catalog.pg_class c
   where c.oid = to_regclass('plm.licensing_consolidation_plan');
  if not coalesce(v_bool, false) then
    raise exception 'CONTRACT: plm.licensing_consolidation_plan must have RLS enabled';
  end if;

  -- Both functions are pinned SECURITY DEFINER and service-role only.
  select count(*) into v_count
    from pg_catalog.pg_proc p
   where p.oid in (
           to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)'),
           to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'))
     and p.prosecdef
     and p.proconfig @> array['search_path=pg_catalog'];
  if v_count <> 2 then
    raise exception 'CONTRACT: both consolidation functions must be security definer with pinned search_path (found %)', v_count;
  end if;
  if has_function_privilege('anon',
       to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)'), 'execute')
     or has_function_privilege('authenticated',
       to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)'), 'execute')
     or has_function_privilege('anon',
       to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'), 'execute')
     or has_function_privilege('authenticated',
       to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'), 'execute') then
    raise exception 'CONTRACT: anon and authenticated must not execute the consolidation functions';
  end if;
  if not has_function_privilege('service_role',
       to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)'), 'execute')
     or not has_function_privilege('service_role',
       to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'), 'execute') then
    raise exception 'CONTRACT: service_role must be able to execute the consolidation functions';
  end if;

  -- ---------------------------------------------------------------------------------
  -- Immutability: content columns cannot change, DELETE is refused, and the apply
  -- lifecycle is the only mutable surface.
  -- ---------------------------------------------------------------------------------
  -- The trigger exists.
  select count(*) into v_count
    from pg_catalog.pg_trigger t
   where t.tgrelid = to_regclass('plm.licensing_consolidation_plan')
     and t.tgname = 'licensing_consolidation_plan_immutable_trg'
     and not t.tgisinternal;
  if v_count <> 1 then
    raise exception 'CONTRACT: the plan immutability trigger is missing';
  end if;

  -- ---------------------------------------------------------------------------------
  -- Complete-capture gate: an unknown / missing capture produces a REFUSED plan with
  -- a recorded reason, never a silent empty preview and never an applyable plan.
  -- ---------------------------------------------------------------------------------
  -- Blank p_entity_source_id is refused (not an empty preview).
  begin
    perform plm.plan_licensing_consolidation('not_a_real_source', v_capture, '   ');
    raise exception 'CONTRACT: blank p_entity_source_id must be refused';
  exception when others then
    get stacked diagnostics v_text = message_text;
    if position('empty filtered identity' in v_text) = 0 then
      raise exception 'CONTRACT: blank filter failed for the wrong reason: %', v_text;
    end if;
  end;

  -- Unknown source system: refused.
  v_plan := plm.plan_licensing_consolidation('not_a_real_source', v_capture);
  v_plan_first_id := v_plan.id;
  v_plan_first_hash := v_plan.plan_hash;
  if v_plan.plan_status <> 'refused' then
    raise exception 'CONTRACT: unknown source_system must produce a refused plan, got %', v_plan.plan_status;
  end if;
  if v_plan.refusal_reason is null
     or position('unsupported qualified capture source' in v_plan.refusal_reason) = 0 then
    raise exception 'CONTRACT: refused plan must record the complete-capture gate, got %', v_plan.refusal_reason;
  end if;
  if v_plan.capture_complete then
    raise exception 'CONTRACT: refused plan must record capture_complete = false';
  end if;
  if v_plan.operations <> '[]'::jsonb then
    raise exception 'CONTRACT: refused plan must carry no operations';
  end if;

  -- Known source, capture that does not exist: refused (null check inside the gate
  -- treats a missing row as not complete).
  v_plan := plm.plan_licensing_consolidation('paramount', v_capture);
  if v_plan.plan_status <> 'refused' then
    raise exception 'CONTRACT: missing paramount capture must produce a refused plan, got %', v_plan.plan_status;
  end if;

  -- ---------------------------------------------------------------------------------
  -- Apply refuses a refused plan.
  -- ---------------------------------------------------------------------------------
  begin
    perform plm.apply_licensing_consolidation(v_plan.id, v_plan.plan_hash);
    raise exception 'CONTRACT: apply of a refused plan must fail';
  exception when others then
    get stacked diagnostics v_text = message_text;
    if position('qualified bounded preview plan required' in v_text) = 0
       and position('cannot be applied' in v_text) = 0 then
      raise exception 'CONTRACT: apply of a refused plan failed for the wrong reason: %', v_text;
    end if;
  end;

  -- ---------------------------------------------------------------------------------
  -- Apply refuses a wrong or malformed expected hash (conflict refusal).
  -- ---------------------------------------------------------------------------------
  begin
    perform plm.apply_licensing_consolidation(v_plan.id, repeat('0', 64));
    raise exception 'CONTRACT: apply with a wrong expected_hash must fail';
  exception when others then
    get stacked diagnostics v_text = message_text;
    if position('exact schema2 plan hash required' in v_text) = 0 then
      raise exception 'CONTRACT: wrong-hash apply failed for the wrong reason: %', v_text;
    end if;
  end;

  begin
    perform plm.apply_licensing_consolidation(v_plan.id, 'not-a-hash');
    raise exception 'CONTRACT: apply with a malformed expected_hash must fail';
  exception when others then
    get stacked diagnostics v_text = message_text;
    if position('exact schema2 plan hash required' in v_text) = 0 then
      raise exception 'CONTRACT: malformed-hash apply failed for the wrong reason: %', v_text;
    end if;
  end;

  -- ---------------------------------------------------------------------------------
  -- Immutability, exercised on a real refused plan row (the only row kind we can
  -- create without capture fixtures).
  -- ---------------------------------------------------------------------------------
  begin
    update plm.licensing_consolidation_plan
       set operations = '[{"op":"update_entity"}]'::jsonb
     where id = v_plan.id;
    raise exception 'CONTRACT: plan content must be immutable';
  exception when others then
    get stacked diagnostics v_text = message_text;
    if position('immutable' in v_text) = 0 then
      raise exception 'CONTRACT: content update refused for the wrong reason: %', v_text;
    end if;
  end;

  begin
    update plm.licensing_consolidation_plan
       set plan_hash = repeat('a', 64)
     where id = v_plan.id;
    raise exception 'CONTRACT: plan_hash must be immutable';
  exception when others then
    get stacked diagnostics v_text = message_text;
    if position('immutable' in v_text) = 0 then
      raise exception 'CONTRACT: hash update refused for the wrong reason: %', v_text;
    end if;
  end;

  begin
    delete from plm.licensing_consolidation_plan where id = v_plan.id;
    raise exception 'CONTRACT: plan rows must never be deletable';
  exception when others then
    get stacked diagnostics v_text = message_text;
    if position('cannot be deleted' in v_text) = 0
       and position('immutable' in v_text) = 0 then
      raise exception 'CONTRACT: delete refused for the wrong reason: %', v_text;
    end if;
  end;

  -- ---------------------------------------------------------------------------------
  -- Idempotent planning: the same (source, capture, hash) returns the same row.
  -- Two refused plans over the same unknown source and same capture share a hash and
  -- therefore share a row. (v_plan was overwritten above by the paramount probe, so
  -- the first plan's identity is carried in v_plan_first_id / v_plan_first_hash.)
  -- ---------------------------------------------------------------------------------
  v_plan2 := plm.plan_licensing_consolidation('not_a_real_source', v_capture);
  if v_plan2.id is distinct from v_plan_first_id then
    raise exception 'CONTRACT: re-planning identical refused input must return the same plan row';
  end if;
  if v_plan2.plan_hash <> v_plan_first_hash then
    raise exception 'CONTRACT: identical refused input must produce an identical plan hash';
  end if;

  -- Different capture, same unknown source: a different plan (capture is identity).
  v_plan2 := plm.plan_licensing_consolidation('not_a_real_source', v_capture2);
  if v_plan2.id = v_plan_first_id then
    raise exception 'CONTRACT: a different capture_id must produce a different plan';
  end if;

  -- ---------------------------------------------------------------------------------
  -- Hash shape is pinned to 64 lowercase hex.
  -- ---------------------------------------------------------------------------------
  if v_plan.plan_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'CONTRACT: plan_hash must be 64 lowercase hex, got %', v_plan.plan_hash;
  end if;

  -- ---------------------------------------------------------------------------------
  -- Write-authorization vocabulary: scrape_consolidation is a kind the Step 1.0 guard
  -- already understands, and the consolidation engine never invents a new kind. Proved
  -- by catalog, not by writing a protected row (that is the guard's own contract).
  -- ---------------------------------------------------------------------------------
  select count(*) into v_count
    from pg_catalog.pg_constraint
   where conrelid = to_regclass('plm.licensing_write_authorization')
     and contype = 'c'
     and pg_get_constraintdef(oid) like '%scrape_consolidation%';
  if v_count < 1 then
    raise exception 'CONTRACT: scrape_consolidation must remain an allowed write_kind on the Step 1.0 guard';
  end if;

  -- The operation vocabulary has no DELETE. The plan function body must never mention
  -- a delete of a canonical entity; asserted on the routine source so a future edit
  -- cannot quietly introduce one.
  select prosrc into v_text
    from pg_catalog.pg_proc
   where oid = to_regprocedure('plm.apply_licensing_consolidation(uuid,text)');
  if position('delete from core.' in lower(v_text)) > 0
     or position('delete from plm.licensing' in lower(v_text)) > 0 then
    raise exception 'CONTRACT: apply must never hard-delete canonical or licensing rows';
  end if;

  -- Engine-private helpers are unreachable by every client, including service.
  foreach t in array array['plm.licensing_consolidation_operation_state(jsonb)','plm.apply_licensing_support_operation(uuid,text,jsonb)'] loop
    if to_regprocedure(t) is null then raise exception 'CONTRACT: private helper missing %',t;end if;
    if has_function_privilege('anon',to_regprocedure(t),'execute') or has_function_privilege('authenticated',to_regprocedure(t),'execute') or has_function_privilege('service_role',to_regprocedure(t),'execute') then raise exception 'CONTRACT: private operation capability exposed %',t;end if;
  end loop;
  if not has_function_privilege('service_role',to_regprocedure('plm.licensing_consolidation_capture_snapshot(text,uuid)'),'execute') or has_function_privilege('authenticated',to_regprocedure('plm.licensing_consolidation_capture_snapshot(text,uuid)'),'execute') then raise exception 'CONTRACT: qualified capture privilege mismatch';end if;
  -- ---------------------------------------------------------------------------------
  -- The engine writes protected canonical columns only through scrape_consolidation.
  -- The create rule (new Property = potential) is pinned by the Step 1.0 guard for
  -- this write_kind; assert the guard still refuses a non-potential create under it.
  -- (No row is written here: we assert the constraint text, which is the enforcement
  -- of record.)
  -- ---------------------------------------------------------------------------------
  select count(*) into v_count
    from pg_catalog.pg_proc
   where oid = to_regprocedure('app.enforce_licensing_write_authority()')
     and prosrc like '%scrape_consolidation%'
     and prosrc like '%potential%';
  if v_count < 1 then
    raise exception 'CONTRACT: the Step 1.0 guard must still pin scrape_consolidation creates to potential';
  end if;

  -- Physical checks reject malformed new plan facts on INSERT, independently of immutable UPDATE guards.
  foreach t in array array['plan_schema_version','capture_snapshot','applied_state'] loop
    begin
      insert into plm.licensing_consolidation_plan
      select (jsonb_populate_record(null::plm.licensing_consolidation_plan,to_jsonb(v_plan)||jsonb_build_object('id',gen_random_uuid(),'plan_hash',encode(extensions.digest(gen_random_uuid()::text,'sha256'),'hex'))||case t when 'plan_schema_version' then jsonb_build_object(t,3) else jsonb_build_object(t,'[]'::jsonb) end)).*;
      raise exception 'CONTRACT: malformed plan fact accepted: %',t;
    exception when check_violation then
      get stacked diagnostics v_text=constraint_name;
      if v_text is distinct from (case t when 'plan_schema_version' then 'licensing_consolidation_plan_schema_version_chk' else 'licensing_consolidation_plan_'||t||'_chk' end) then raise exception 'CONTRACT: wrong physical check rejected %: %',t,v_text;end if;
    end;
  end loop;
  raise notice 'hash-pinned licensing consolidation contracts verified';
end;
$contracts$;

rollback;

-- Current native physical planner/apply/inverse regressions; each fixture rolls back.
begin;
-- Invented current-native fixtures use the real protected-column authorizations.
insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at) values(pg_backend_pid(),txid_current(),'core.licensor','scrape_consolidation',gen_random_uuid(),repeat('1',64),'issue2336-native-contract',array['name','code','status'],clock_timestamp()+interval '1 minute');
insert into core.licensor(id,name,code,status) values('23360000-0000-0000-0000-000000000001','ZZ Native Contract2336','ZZ2336N','active');
insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at) values(pg_backend_pid(),txid_current(),'core.property','licensing_review_create',gen_random_uuid(),repeat('2',64),'issue2336-native-contract',array['licensor_id','name','code','status'],clock_timestamp()+interval '1 minute');
insert into core.property(id,licensor_id,name,code,status) values('23360000-0000-0000-0000-000000000002','23360000-0000-0000-0000-000000000001','Synthetic original','ZZ2336NP','potential');
insert into core.character(id,licensor_id,name) values('23360000-0000-0000-0000-000000000004','23360000-0000-0000-0000-000000000001','Synthetic canonical character');
insert into core.style_guide(id,licensor_id,name,property_id) values('23360000-0000-0000-0000-000000000005','23360000-0000-0000-0000-000000000001','Synthetic guide','23360000-0000-0000-0000-000000000002');
insert into plm.pmt_capture(capture_id,status,capture_kind,source_system,source_url,library_name,started_at,completed_at,captured_by,private_source_commit,manifest_sha256,portal_global_asset_count,licensed_title_count,licensed_property_selection_count,property_result_row_count,unique_asset_count,metadata_batch_count,validated_at,validation_passed)
 values('23360000-0000-0000-0000-000000000020','complete','full','paramount_creative_library','https://fixture.invalid','Synthetic test','2026-10-10 12:00Z','2026-10-10 12:01Z','issue2336-test',repeat('a',40),repeat('b',64),0,1,1,1,0,0,now(),true);
insert into plm.pmt_authorized_title(capture_id,authorized_title_key,authorized_title_name,capture_status,unique_asset_count,full_metadata_count,source_hash) values('23360000-0000-0000-0000-000000000020','title','Synthetic title','captured',0,0,repeat('c',64));
insert into plm.pmt_property(capture_id,property_source_id,property_name,is_licensed_selection,source_hash) values('23360000-0000-0000-0000-000000000020','0007','Synthetic original',true,repeat('d',64));
insert into plm.pmt_character(capture_id,character_source_id,character_name,source_hash) values('23360000-0000-0000-0000-000000000020','0008','Synthetic native character',repeat('e',64));
insert into plm.pmt_collection(capture_id,collection_source_id,collection_name,paramount_term,source_hash) values('23360000-0000-0000-0000-000000000020','0009','Synthetic native collection','Collection',repeat('f',64));
insert into plm.pmt_authorized_title_property(capture_id,authorized_title_key,property_source_id,mapping_status,source_evidence,paramount_property_name,source_hash) values('23360000-0000-0000-0000-000000000020','title','0007','mapped','exact_property_selection','Synthetic original',repeat('1',64));
insert into plm.pmt_property_character(capture_id,property_source_id,character_source_id,source_evidence,source_hash) values('23360000-0000-0000-0000-000000000020','0007','0008','explicit_cascading_pair',repeat('2',64));
insert into plm.pmt_property_collection(capture_id,property_source_id,collection_source_id,source_evidence,source_hash) values('23360000-0000-0000-0000-000000000020','0007','0009','explicit_cascading_pair',repeat('2',64));
insert into plm.source_resolution(source_system,entity_kind,source_id,core_property_id,resolution_status) values('paramount','property','0007','23360000-0000-0000-0000-000000000002','matched');
insert into plm.source_resolution(source_system,entity_kind,source_id,core_character_id,resolution_status) values('paramount','character','0008','23360000-0000-0000-0000-000000000004','matched');
insert into plm.source_resolution(source_system,entity_kind,source_id,core_style_guide_id,resolution_status) values('paramount','style_guide','0009','23360000-0000-0000-0000-000000000005','matched');
insert into plm.licensing_source_scope values('23360000-0000-0000-0000-000000000001','paramount','canonical_identity','entity','property',now(),'synthetic test'),('23360000-0000-0000-0000-000000000001','paramount','canonical_identity','entity','character',now(),'synthetic test'),('23360000-0000-0000-0000-000000000001','paramount','canonical_identity','entity','style_guide',now(),'synthetic test'),('23360000-0000-0000-0000-000000000001','paramount','relationship_evidence','relationship','property_character',now(),'synthetic test'),('23360000-0000-0000-0000-000000000001','paramount','relationship_evidence','relationship','property_style_guide',now(),'synthetic test');
do $test$ declare p plm.licensing_consolidation_plan;q plm.licensing_consolidation_plan;r plm.licensing_consolidation_plan;rejected boolean:=false;native_capture uuid;native_table text;phase integer;pair_id uuid;pair_created timestamptz;begin
 begin perform plm.plan_licensing_consolidation('paramount','23360000-0000-0000-0000-000000000020','7');exception when others then rejected:=true;end;if not rejected then raise exception 'leading zero ID corrupted';end if;
 begin update plm.pmt_property set property_name='Unsafe source mutation' where capture_id='23360000-0000-0000-0000-000000000020';raise exception 'completed native property mutation accepted';exception when sqlstate 'P0001' then if sqlerrm='completed native property mutation accepted' then raise;end if;end;
 p:=plm.plan_licensing_consolidation('paramount','23360000-0000-0000-0000-000000000020');q:=plm.apply_licensing_consolidation(p.id,p.plan_hash);
 if q.entity_operation_count<>3 or q.relationship_operation_count<>4 or not exists(select 1 from core.property_style_guide where is_current) then raise exception 'real Collection/StyleGuide support missing';end if;
 r:=plm.apply_licensing_consolidation(q.id,q.plan_hash);if r.id<>q.id or r.applied_state is distinct from q.applied_state then raise exception 'exact repeated native apply changed state';end if;
 begin
 update core.property_character_source_edge set metadata=metadata||jsonb_build_object('changed_poststate',true) where source_system='paramount' and is_current;
 perform plm.plan_licensing_consolidation_rollback(q.id,encode(extensions.digest(q.applied_state::text,'sha256'),'hex'));raise exception 'changed physical poststate accepted for inverse';
 exception when sqlstate '40001' then null;end;
 begin
 delete from plm.licensing_source_scope where source_system='paramount' and licensor_id='23360000-0000-0000-0000-000000000001';
 perform plm.plan_licensing_consolidation_rollback(q.id,encode(extensions.digest(q.applied_state::text,'sha256'),'hex'));raise exception 'revoked current source authority accepted for inverse';
 exception when sqlstate 'P0001' then if sqlerrm='revoked current source authority accepted for inverse' then raise;end if;end;
 r:=plm.plan_licensing_consolidation_rollback(q.id,encode(extensions.digest(q.applied_state::text,'sha256'),'hex'));r:=plm.apply_licensing_consolidation(r.id,r.plan_hash);
 if exists(select 1 from core.property_character_source_edge where is_current) or exists(select 1 from core.property_style_guide_current) or (select count(*) from core.property_character_source_edge)<>1 or (select count(*) from core.taxonomy_source_ref)<>3 then raise exception 'physical conditional rollback failed/history deleted';end if;
 if q.id=(select rollback_of from plm.licensing_consolidation_plan where id=r.id) and (select plan_status from plm.licensing_consolidation_plan where id=q.id)='applied' then -- Distinct immutable captures exercise real missing-support retirement and reactivation.
 select created_at into pair_created from core.property_character_associations where property_id='23360000-0000-0000-0000-000000000002' and character_id='23360000-0000-0000-0000-000000000004';
 for phase in 1..3 loop
  native_capture:=gen_random_uuid();
  insert into plm.pmt_capture select (jsonb_populate_record(null::plm.pmt_capture,to_jsonb(c)||jsonb_build_object('capture_id',native_capture,'started_at','2026-10-11 12:00Z'::timestamptz+phase*interval '1 minute','completed_at','2026-10-11 12:01Z'::timestamptz+phase*interval '1 minute'))).* from plm.pmt_capture c where capture_id='23360000-0000-0000-0000-000000000020';
  foreach native_table in array array['pmt_authorized_title','pmt_property','pmt_character','pmt_collection','pmt_authorized_title_property','pmt_property_collection','pmt_property_character'] loop
   if phase=2 and native_table='pmt_property_character' then continue;end if;
   execute format('insert into plm.%I select (jsonb_populate_record(null::plm.%I,to_jsonb(t)||jsonb_build_object(''capture_id'',$1))).* from plm.%I t where capture_id=$2',native_table,native_table,native_table) using native_capture,'23360000-0000-0000-0000-000000000020'::uuid;
  end loop;
  p:=plm.plan_licensing_consolidation('paramount',native_capture);q:=plm.apply_licensing_consolidation(p.id,p.plan_hash);
  if phase=2 then
   if exists(select 1 from core.property_character_associations_current where property_id='23360000-0000-0000-0000-000000000002') then raise exception 'missing last direct support kept pair current';end if;
  else
   if not exists(select 1 from core.property_character_associations_current where property_id='23360000-0000-0000-0000-000000000002') then raise exception 'restored exact native support failed reactivation';end if;
  end if;
  if not exists(select 1 from core.property_character_associations where property_id='23360000-0000-0000-0000-000000000002' and character_id='23360000-0000-0000-0000-000000000004' and created_at=pair_created) then raise exception 'reactivation replaced historical pair identity or timestamp';end if;
 end loop;
 if (select count(*) from core.property_character_source_edge where source_system='paramount')<3 or (select count(*) from core.property_character_source_edge where source_system='paramount' and is_current)<>1 then raise exception 'physical support retirement/reactivation lost history';end if;
 begin
 native_capture:=gen_random_uuid();
 insert into plm.pmt_capture select (jsonb_populate_record(null::plm.pmt_capture,to_jsonb(c)||jsonb_build_object('capture_id',native_capture,'started_at','2026-10-11 12:10Z'::timestamptz,'completed_at','2026-10-11 12:11Z'::timestamptz))).* from plm.pmt_capture c where capture_id='23360000-0000-0000-0000-000000000020';
 foreach native_table in array array['pmt_authorized_title','pmt_property','pmt_character','pmt_collection','pmt_authorized_title_property','pmt_property_collection','pmt_property_character'] loop
 execute format('insert into plm.%I select (jsonb_populate_record(null::plm.%I,to_jsonb(t)||jsonb_build_object(''capture_id'',$1))).* from plm.%I t where capture_id=$2',native_table,native_table,native_table) using native_capture,'23360000-0000-0000-0000-000000000020'::uuid;
 end loop;
 update core.property_character_source_edge set metadata=metadata-'engine_schema_version' where source_system='paramount' and is_current;
 r:=plm.plan_licensing_consolidation('paramount',native_capture);
 if r.plan_status<>'refused' or r.refusal_reason not like '%incompatible namespace%' then raise exception 'NULL legacy source provenance was accepted or rewritten: % / %',r.plan_status,r.refusal_reason;end if;
 raise exception 'restore deliberately invalid fixture' using errcode='P0002';
 exception when sqlstate 'P0002' then null;end;
 raise notice 'Paramount native leading-zero IDs, actual Collection support, conditional physical rollback/history PASS';else raise exception 'audit lineage lost';end if;
end $test$;

rollback;
begin;
-- Invented current-native fixtures use the real protected-column authorizations.
insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at) values(pg_backend_pid(),txid_current(),'core.licensor','scrape_consolidation',gen_random_uuid(),repeat('1',64),'issue2336-native-contract',array['name','code','status'],clock_timestamp()+interval '1 minute');
insert into core.licensor(id,name,code,status) values('23360000-0000-0000-0000-000000000001','ZZ Native Contract2336','ZZ2336N','active');
insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at) values(pg_backend_pid(),txid_current(),'core.property','licensing_review_create',gen_random_uuid(),repeat('2',64),'issue2336-native-contract',array['licensor_id','name','code','status'],clock_timestamp()+interval '1 minute');
insert into core.property(id,licensor_id,name,code,status) values('23360000-0000-0000-0000-000000000002','23360000-0000-0000-0000-000000000001','Synthetic original','ZZ2336NP','potential');
insert into core.character(id,licensor_id,name) values('23360000-0000-0000-0000-000000000004','23360000-0000-0000-0000-000000000001','Synthetic canonical character');
insert into core.style_guide(id,licensor_id,name,property_id) values('23360000-0000-0000-0000-000000000005','23360000-0000-0000-0000-000000000001','Synthetic guide','23360000-0000-0000-0000-000000000002');
insert into plm.nbcu_capture(id,capture_key,status,source_repository,source_commit_sha,source_manifest_sha256,portal_base_url,source_captured_at,load_completed_at,expected_counts,observed_counts,raw_summary,created_by) values('23360000-0000-0000-0000-000000000010','issue2336-nbcu-native','complete','fixture',repeat('a',40),repeat('b',64),'https://fixture.invalid','2026-10-10 12:00Z','2026-10-10 12:01Z','{"assets":0,"properties":1,"characters":1,"style_guides":0,"scopes":1,"ip_family_property":0,"property_character":1,"asset_property":0,"asset_character":0,"asset_style_guide":0,"style_guide_property":0,"asset_ip_family":0}'::jsonb,'{"assets":0,"properties":1,"characters":1,"style_guides":0,"scopes":1,"ip_family_property":0,"property_character":1,"asset_property":0,"asset_character":0,"asset_style_guide":0,"style_guide_property":0,"asset_ip_family":0}'::jsonb,'{}','test');
insert into plm.nbcu_scope(capture_id,scope_key,scope_label,scope_href,page_count,indexed_rows,unique_assets,terminal,source_files,raw) values('23360000-0000-0000-0000-000000000010','href-sha256:'||repeat('c',64),'fixture','https://fixture.invalid/scope',0,0,0,true,'[]','{}');
insert into plm.nbcu_property(capture_id,property_key,property_source_id,property_label,source_kind,source_url,source_captured_at,raw) values('23360000-0000-0000-0000-000000000010','source-id:700','700','Exact Official NBCU','property','https://fixture.invalid',now(),'{}');
insert into plm.nbcu_character(capture_id,character_key,character_source_id,character_label,source_url,source_captured_at,raw) values('23360000-0000-0000-0000-000000000010','701','701','Synthetic native character','https://fixture.invalid',now(),'{}');
insert into plm.nbcu_property_character(capture_id,property_key,character_key,property_label,character_label,evidence_type,evidence_value,source_captured_at,source_url,raw) values('23360000-0000-0000-0000-000000000010','source-id:700','701','Exact Official NBCU','Synthetic native character','exact_native_pair','invented direct fixture',now(),'https://fixture.invalid','{}');
insert into plm.source_resolution(source_system,entity_kind,source_id,core_property_id,resolution_status) values('nbcu','property','source-id:700','23360000-0000-0000-0000-000000000002','matched');
insert into plm.source_resolution(source_system,entity_kind,source_id,core_character_id,resolution_status) values('nbcu','character','701','23360000-0000-0000-0000-000000000004','matched');
insert into plm.licensing_source_scope values('23360000-0000-0000-0000-000000000001','nbcu','canonical_identity','entity','property',now(),'synthetic test'),('23360000-0000-0000-0000-000000000001','nbcu','canonical_identity','entity','character',now(),'synthetic test'),('23360000-0000-0000-0000-000000000001','nbcu','relationship_evidence','relationship','property_character',now(),'synthetic test');
-- Creative metadata-only Property remains raw evidence, even with a durable mapping.
insert into plm.nbcu_property(capture_id,property_key,property_label,source_kind,source_url,source_captured_at,raw) values('23360000-0000-0000-0000-000000000010','metadata-label-sha256:'||repeat('f',64),'Creative-only unrelated title','asset_metadata_label','https://fixture.invalid',now(),'{}');
update plm.nbcu_capture set expected_counts=jsonb_set(expected_counts,'{properties}','2'),observed_counts=jsonb_set(observed_counts,'{properties}','2')||jsonb_build_object('asset_metadata_values',0,'asset_scopes',0) where id='23360000-0000-0000-0000-000000000010';
insert into plm.source_resolution(source_system,entity_kind,source_id,core_property_id,resolution_status) values('nbcu','property','metadata-label-sha256:'||repeat('f',64),'23360000-0000-0000-0000-000000000002','matched');
do $test$ declare p plm.licensing_consolidation_plan;q plm.licensing_consolidation_plan;rejected boolean:=false;n bigint;begin
 begin perform plm.plan_licensing_consolidation('nbcu','23360000-0000-0000-0000-000000000010','700');exception when others then rejected:=true;end;if not rejected then raise exception 'NBCU fallback erroneously accepted';end if;
 begin
 update plm.nbcu_property_character set evidence_type='cooccurrence' where capture_id='23360000-0000-0000-0000-000000000010';
 perform plm.licensing_consolidation_capture_snapshot('nbcu','23360000-0000-0000-0000-000000000010');raise exception 'cooccurrence became direct source authority';
 exception when sqlstate 'P0001' then if sqlerrm='cooccurrence became direct source authority' then raise;end if;end;
 begin
 update plm.nbcu_capture set expected_counts=jsonb_set(expected_counts,'{asset_property}','null') where id='23360000-0000-0000-0000-000000000010';
 perform plm.licensing_consolidation_capture_snapshot('nbcu','23360000-0000-0000-0000-000000000010');raise exception 'JSON null native expected count accepted';
 exception when sqlstate 'P0001' then if sqlerrm='JSON null native expected count accepted' then raise;end if;end;
 p:=plm.plan_licensing_consolidation('nbcu','23360000-0000-0000-0000-000000000010');
 begin
 update plm.source_resolution set resolution_status='ignored',core_character_id=null where source_system='nbcu' and entity_kind='character' and source_id='701';
 perform plm.apply_licensing_consolidation(p.id,p.plan_hash);raise exception 'changed durable decision accepted by apply';
 exception when sqlstate '40001' then null;end;
 if exists(select 1 from core.taxonomy_source_ref where source_system='nbcu') then raise exception 'stale decision refusal wrote provenance';end if;
 begin
 update core.character set licensor_id=null where id='23360000-0000-0000-0000-000000000004';
 perform plm.apply_licensing_consolidation(p.id,p.plan_hash);raise exception 'missing owner accepted by apply';
 exception when sqlstate 'P0001' then if sqlerrm='missing owner accepted by apply' then raise;end if;end;
 q:=plm.apply_licensing_consolidation(p.id,p.plan_hash);
 if q.plan_status<>'applied' or q.entity_operation_count<3 or q.relationship_operation_count<>2 then raise exception 'physical counters missing';end if;
 if (select name from core.property where id='23360000-0000-0000-0000-000000000002')<>'Exact Official NBCU' or not exists(select 1 from core.property_alias where alias='Synthetic original' and not cross_app_certified and approved_by is null) then raise exception 'protected official rename/prior alias missing';end if;
 if exists(select 1 from core.taxonomy_source_ref where source_system='nbcu' and source_id like '%metadata-label-sha256%') or exists(select 1 from core.property_alias where property_id='23360000-0000-0000-0000-000000000002' and alias='Creative-only unrelated title') or not exists(select 1 from plm.nbcu_property where capture_id='23360000-0000-0000-0000-000000000010' and source_kind='asset_metadata_label') then raise exception 'Creative-only raw Property became canonical authority or was lost';end if;
 if (select count(*) from core.taxonomy_source_ref where source_system='nbcu' and missing_since is null)<>2 or (select count(*) from core.property_character_source_edge where source_system='nbcu' and is_current)<>1 or not exists(select 1 from core.property_character_associations where is_current) then raise exception 'real support/pair writes missing';end if;
 begin
 perform plm.plan_licensing_consolidation_rollback(q.id,encode(extensions.digest(q.applied_state::text,'sha256'),'hex'));raise exception 'rename inverse ignored retained-alias conflict';
 exception when sqlstate 'P0001' then if sqlerrm='rename inverse ignored retained-alias conflict' then raise;end if;end;
 if (select name from core.property where id='23360000-0000-0000-0000-000000000002')<>'Exact Official NBCU' or not exists(select 1 from core.property_alias where property_id='23360000-0000-0000-0000-000000000002' and alias='Synthetic original') then raise exception 'refused rename inverse changed official name or old alias';end if;
 select count(*) into n from plm.licensing_write_guard_audit;
 -- Idempotency succeeds before no-write capture recheck, even after a new complete root.
 insert into plm.nbcu_capture(id,capture_key,status,source_repository,source_commit_sha,source_manifest_sha256,portal_base_url,source_captured_at,load_completed_at,expected_counts,observed_counts,raw_summary,created_by) select '23360000-0000-0000-0000-000000000011','issue2336-later-native',status,source_repository,source_commit_sha,source_manifest_sha256,portal_base_url,'2026-10-11 12:00Z','2026-10-11 12:01Z',expected_counts,observed_counts,raw_summary,created_by from plm.nbcu_capture where id='23360000-0000-0000-0000-000000000010';
 q:=plm.apply_licensing_consolidation(p.id,p.plan_hash);
 if (select count(*) from plm.licensing_write_guard_audit)<>n then raise exception 'idempotent retry consumed new authorization';end if;
 raise notice 'NBCU native namespace, real source refs/pair, protected alias and exact idempotent physical apply PASS';
end $test$;
rollback;

begin;
-- Invented current-native fixtures use the real protected-column authorizations.
insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at) values(pg_backend_pid(),txid_current(),'core.licensor','scrape_consolidation',gen_random_uuid(),repeat('1',64),'issue2336-native-contract',array['name','code','status'],clock_timestamp()+interval '1 minute');
insert into core.licensor(id,name,code,status) values('23360000-0000-0000-0000-000000000001','ZZ Native Contract2336','ZZ2336N','active');
insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at) values(pg_backend_pid(),txid_current(),'core.property','licensing_review_create',gen_random_uuid(),repeat('2',64),'issue2336-native-contract',array['licensor_id','name','code','status'],clock_timestamp()+interval '1 minute');
insert into core.property(id,licensor_id,name,code,status) values('23360000-0000-0000-0000-000000000002','23360000-0000-0000-0000-000000000001','Synthetic original','ZZ2336NP','potential');
insert into core.character(id,licensor_id,name) values('23360000-0000-0000-0000-000000000004','23360000-0000-0000-0000-000000000001','Synthetic canonical character');
insert into core.style_guide(id,licensor_id,name,property_id) values('23360000-0000-0000-0000-000000000005','23360000-0000-0000-0000-000000000001','Synthetic guide','23360000-0000-0000-0000-000000000002');
do $opa_native$ declare c uuid:='23360000-0000-0000-0000-000000000030';x record;h text;root_hash text;plan plm.licensing_consolidation_plan;applied plm.licensing_consolidation_plan;inverse plm.licensing_consolidation_plan;begin
 insert into plm.opa_capture(id,capture_key,source_repository,source_commit_sha,source_manifest_sha256,source_captured_at,status,load_completed_at,expected_scope_count,expected_unique_property_count,expected_unique_character_count,expected_scope_membership_count,expected_cross_scope_property_count,expected_relationship_count,expected_duplicate_pair_count,observed_unique_property_count,observed_unique_character_count,observed_scope_membership_count,observed_cross_scope_property_count,observed_relationship_count,observed_duplicate_pair_count,created_by)
 values(c,'issue2336-opa-native','fixture',repeat('a',40),repeat('b',64),'2026-10-10 12:00Z','complete','2026-10-10 12:01Z',2,2,2,2,0,2,0,2,2,2,0,2,0,'test');
 for x in select * from (values ('disney_home_standard','Disney','21','49',400,401),('lucas_home_standard','Lucas','462','50',402,403)) q(scope_key,branch,template_id,workflow_id,property_id,character_id) loop
  h:=encode(extensions.digest(convert_to(x.property_id::text,'UTF8')||decode('00','hex')||convert_to('Synthetic original','UTF8')||decode('00','hex')||convert_to('900','UTF8')||decode('00','hex')||convert_to(x.character_id::text,'UTF8')||decode('00','hex')||convert_to('Synthetic native character','UTF8')||decode('00','hex')||convert_to('999','UTF8'),'sha256'),'hex');
  insert into plm.opa_capture_scope(capture_id,scope_key,region,branch,lob,submission_type,template_id,workflow_id,source_sha256,expected_property_count,expected_character_count,expected_relationship_count,expected_relationship_sha256,authentication_evidence_sha256,authenticated_at,observed_property_count,observed_character_count,observed_relationship_count,observed_duplicate_pair_count,observed_relationship_sha256,status,finished_at)
   values(c,x.scope_key,'North America',x.branch,'200','Standard',x.template_id,x.workflow_id,repeat('c',64),1,1,1,h,repeat('d',64),now(),1,1,1,0,h,'complete',now());
  insert into plm.opa_property_character_capture(capture_id,scope_key,chunk_key,chunk_sha256,licensed_property_id,property_name,option_source_id,character_id,character_name,brand_property_id,source_row_sha256)
   values(c,x.scope_key,'chunk',repeat('e',64),x.property_id,'Synthetic original',900,x.character_id,'Synthetic native character',999,h);
  insert into plm.source_resolution(source_system,entity_kind,source_id,core_property_id,resolution_status) values('disney_opa','property',x.property_id::text,'23360000-0000-0000-0000-000000000002','matched');
  insert into plm.source_resolution(source_system,entity_kind,source_id,core_character_id,resolution_status) values('disney_opa','character',x.character_id::text,'23360000-0000-0000-0000-000000000004','matched');
 end loop;
 select encode(extensions.digest(convert_to(string_agg(source_row_sha256,e'\n' order by source_row_sha256),'UTF8'),'sha256'),'hex') into root_hash from plm.opa_property_character_capture where capture_id=c;
 update plm.opa_capture set observed_relationship_sha256=root_hash where id=c;
 insert into plm.licensing_source_scope values('23360000-0000-0000-0000-000000000001','disney_opa','canonical_identity','entity','property',now(),'synthetic test'),('23360000-0000-0000-0000-000000000001','disney_opa','canonical_identity','entity','character',now(),'synthetic test'),('23360000-0000-0000-0000-000000000001','disney_opa','relationship_evidence','relationship','property_character',now(),'synthetic test');
 begin perform plm.plan_licensing_consolidation('disney_opa',c,'999');raise exception 'brand ID incorrectly accepted as licensed Property';exception when sqlstate '22023' then null;end;
 begin update plm.opa_capture_scope set authentication_evidence_sha256=null,authenticated_at=null where capture_id=c and scope_key='lucas_home_standard';perform plm.licensing_consolidation_capture_snapshot('disney_opa',c);raise exception 'unauthenticated complete route accepted';exception when sqlstate 'P0001' then if sqlerrm='unauthenticated complete route accepted' then raise;end if;end;
 begin update plm.opa_capture_scope set expected_relationship_sha256=repeat('f',64) where capture_id=c;perform plm.licensing_consolidation_capture_snapshot('disney_opa',c);raise exception 'incorrect route manifest accepted';exception when sqlstate 'P0001' then if sqlerrm='incorrect route manifest accepted' then raise;end if;end;
 plan:=plm.plan_licensing_consolidation('disney_opa',c);applied:=plm.apply_licensing_consolidation(plan.id,plan.plan_hash);
 if applied.plan_status<>'applied' or (select count(*) from core.taxonomy_source_ref where source_system='disney_opa' and missing_since is null)<>4 or (select count(*) from core.property_character_source_edge where source_system='disney_opa' and is_current)<>1 then raise exception 'approved two-route physical OPA provenance missing';end if;
 inverse:=plm.plan_licensing_consolidation_rollback(applied.id,encode(extensions.digest(applied.applied_state::text,'sha256'),'hex'));inverse:=plm.apply_licensing_consolidation(inverse.id,inverse.plan_hash);
 if exists(select 1 from core.property_character_source_edge where source_system='disney_opa' and is_current) or not exists(select 1 from core.property_character_source_edge where source_system='disney_opa' and not is_current) then raise exception 'OPA inverse erased history or retained current support';end if;
 raise notice 'OPA exact approved routes/actual hash/counts/licensed property namespace/physical inverse PASS';
end $opa_native$;
rollback;
