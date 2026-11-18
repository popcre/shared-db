-- Rollback-safe contracts for 20261117020100 / issue #6463 (MG groups are division-specific).
begin;

do $$
declare
  v_s text := upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  v_run uuid; v_res jsonb; v_old uuid; v_other_old uuid; v_property uuid;
  v_lic uuid; v_sp_lic uuid; v_parent bigint; v_sp_parent bigint; v_theme_parent bigint;
  v_stale_refused boolean := false;
begin
  delete from coldlion.merch_group_detail where mg_type_code in ('05','06');
  -- Exercise the division-aware app_parent branch, including on CI without the app table.
  create schema if not exists dflow_prod;
  if to_regclass('dflow_prod."merchGroup"') is null then
    create table dflow_prod."merchGroup"(mg_id serial primary key, mg_code text,
      "mgTypeCode" text, parent_id int, "divisionCode_fk" text,
      mg_desc text, is_active boolean, "modTime" timestamptz);
  end if;
  alter table dflow_prod."merchGroup" add column if not exists "divisionCode_fk" text;

  -- Simulate art-theme licensors left by the earlier unscoped feed.
  perform set_config('app.core_licensor_writer', 'mg05_feed', true);
  insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
  select pg_backend_pid(),txid_current(),'core.licensor','scrape_consolidation',gen_random_uuid(),repeat(g::text,64),'6463-contract',array['name','code','status'],clock_timestamp()+interval '1 minute'
    from generate_series(1,2) g;
  insert into core.licensor(name,code,status) values('OLD ABSTRACT '||v_s,'D'||v_s,'active') returning id into v_old;
  insert into core.licensor(name,code,status) values('OLD ANIMAL '||v_s,'R'||v_s,'potential') returning id into v_other_old;
  insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
  values(pg_backend_pid(),txid_current(),'core.property','licensing_review_create',gen_random_uuid(),repeat('3',64),'6463-contract',array['licensor_id','name','code','status'],clock_timestamp()+interval '1 minute');
  insert into core.property(licensor_id,name,code,status)
  values(v_old,'RETAINED THEME '||v_s,'K'||v_s,'active') returning id into v_property;
  insert into coldlion.sync_run(endpoint, requested_by) values ('/merchGroupDetails','6463-contract') returning id into v_run;
  insert into coldlion.merch_group_header(company_code,division_code,mg_type_code,mg_type_desc,run_id,fetched_at,source_hash,first_seen_at,last_seen_at)
  values ('FIX6463','CW001','05','Licensor',v_run,now(),repeat('e',64),now(),now()),
         ('FIX6463','SP001','05','Licensor',v_run,now(),repeat('e',64),now(),now()),
         ('FIX6463','EH001','05','Art Theme',v_run,now(),repeat('f',64),now(),now()),
         ('FIX6463','CW001','06','Property',v_run,now(),repeat('e',64),now(),now()),
         ('FIX6463','SP001','06','Property',v_run,now(),repeat('e',64),now(),now()),
         ('FIX6463','EH001','06','Little Theme',v_run,now(),repeat('f',64),now(),now());
  insert into coldlion.merch_group_detail(company_code,division_code,mg_type_code,mg_code,mg_category,run_id,fetched_at,source_hash,first_seen_at,last_seen_at,mg_desc,active) values
   ('FIX6463','CW001','05','L'||v_s,'',v_run,now(),repeat('a',64),now(),now(),'REAL LICENSOR '||v_s,'Y'),
   ('FIX6463','SP001','05','S'||v_s,'',v_run,now(),repeat('a',64),now(),now(),'SP LICENSOR '||v_s,'Y'),
   ('FIX6463','EH001','05','D'||v_s,'',v_run,now(),repeat('a',64),now(),now(),'OLD ABSTRACT '||v_s,'Y'),
   ('FIX6463','EH001','05','R'||v_s,'',v_run,now(),repeat('a',64),now(),now(),'OLD ANIMAL '||v_s,'Y'),
   ('FIX6463','EH001','05','T'||v_s,'',v_run,now(),repeat('a',64),now(),now(),'ABSTRACT '||v_s,'Y');

  v_res := plm.sync_core_licensor_from_coldlion(false);
  if not exists (select 1 from core.licensor where id = v_old and status::text = 'active' and not (metadata ? 'mg05_retired')) then
    raise exception 'dry run retired an art-theme licensor';
  end if;
  v_res := plm.sync_core_licensor_from_coldlion(true);
  if not exists (select 1 from core.licensor where code = 'L'||v_s and status::text = 'active') then
    raise exception 'licensed-division MG05 not made a licensor: %', v_res;
  end if;
  if exists (select 1 from core.licensor where code = 'T'||v_s) then
    raise exception 'EH001 art theme became a licensor';
  end if;
  if not exists (select 1 from core.licensor where id = v_old and status::text = 'inactive'
                 and metadata->'mg05_retired'->>'previous_status' = 'active'
                 and metadata->'mg05_retired'->>'code' = 'D'||v_s)
     or not exists (select 1 from core.licensor where id = v_other_old and status::text = 'inactive'
                     and metadata->'mg05_retired'->>'previous_status' = 'potential') then
    raise exception 'pre-existing EH001 licensors were not retired recoverably';
  end if;
  if not exists (select 1 from core.property where id = v_property and licensor_id = v_old and status::text = 'active') then
    raise exception 'retirement changed a retained property or its reference';
  end if;

  select id into strict v_lic from core.licensor where code = 'L'||v_s;
  select id into strict v_sp_lic from core.licensor where code = 'S'||v_s;
  insert into dflow_prod."merchGroup"(mg_code,"mgTypeCode","divisionCode_fk")
  values('L'||v_s,'05','CW001') returning mg_id into v_parent;
  insert into dflow_prod."merchGroup"(mg_code,"mgTypeCode","divisionCode_fk")
  values('S'||v_s,'05','SP001') returning mg_id into v_sp_parent;
  insert into dflow_prod."merchGroup"(mg_code,"mgTypeCode","divisionCode_fk")
  values('D'||v_s,'05','EH001') returning mg_id into v_theme_parent;
  insert into dflow_prod."merchGroup"(mg_code,"mgTypeCode","divisionCode_fk",parent_id) values
    ('P'||v_s,'06','CW001',v_parent), ('Q'||v_s,'06','SP001',v_sp_parent),
    ('P'||v_s,'06','EH001',v_theme_parent), -- Same code in an unrelated division must not compete.
    ('X'||v_s,'06','CW001',v_sp_parent),  -- A parent in another licensed division is not a match.
    ('E'||v_s,'06','EH001',v_theme_parent);
  insert into coldlion.merch_group_detail(company_code,division_code,mg_type_code,mg_code,mg_category,run_id,fetched_at,source_hash,first_seen_at,last_seen_at,mg_desc,active) values
    ('FIX6463','CW001','06','P'||v_s,'',v_run,now(),repeat('a',64),now(),now(),'CW PROPERTY '||v_s,'Y'),
    ('FIX6463','SP001','06','Q'||v_s,'',v_run,now(),repeat('a',64),now(),now(),'SP PROPERTY '||v_s,'Y'),
    ('FIX6463','CW001','06','X'||v_s,'',v_run,now(),repeat('a',64),now(),now(),'WRONG PARENT '||v_s,'Y'),
    ('FIX6463','EH001','06','E'||v_s,'',v_run,now(),repeat('a',64),now(),now(),'LITTLE THEME '||v_s,'Y');
  v_res := plm.sync_core_property_from_coldlion(true);
  if not exists (select 1 from core.property where code = 'P'||v_s and licensor_id = v_lic
                  and status::text = 'active' and metadata->'coldlion_sync'->>'licensor_from' = 'app_parent')
     or not exists (select 1 from core.property where code = 'Q'||v_s and licensor_id = v_sp_lic
                     and status::text = 'active' and metadata->'coldlion_sync'->>'licensor_from' = 'app_parent') then
    raise exception 'MG06 not placed under its same-division parent: %', v_res;
  end if;
  if exists (select 1 from core.property where code in ('X'||v_s,'E'||v_s))
     or (v_res->>'skipped_no_licensor')::int is distinct from 1 then
    raise exception 'cross-division parent or EH001 MG06 accepted: %', v_res;
  end if;

  -- Fresh nonlicensed rows cannot mask stale licensed data.
  update coldlion.merch_group_detail set last_seen_at = now() - interval '4 days'
   where mg_type_code = '06' and division_code in ('CW001','SP001');
  begin
    perform plm.sync_core_property_from_coldlion(true);
  exception when raise_exception then
    if sqlerrm not like '#6194:%' then raise; end if;
    v_stale_refused := true;
  end;
  if not v_stale_refused then raise exception 'fresh EH001 rows masked stale licensed MG06'; end if;
  delete from coldlion.merch_group_detail where mg_type_code = '06' and division_code in ('CW001','SP001');
  v_res := plm.sync_core_property_from_coldlion(true);
  if v_res->>'note' is distinct from 'no ColdLion MG06 rows landed; nothing to do' then
    raise exception 'EH001-only MG06 did not return the no-rows note: %', v_res;
  end if;
end;
$$;

rollback;
