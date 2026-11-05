-- #5628 / #5646: populated reader behavior; disposable database only.
-- All fixtures roll back. This test changes no reader, grant or matching rule.
begin;

do $fixtures$
declare
  lic uuid := gen_random_uuid(); prop uuid := gen_random_uuid();
  ca uuid := gen_random_uuid(); cb uuid := gen_random_uuid();
  entitled uuid := gen_random_uuid(); denied uuid := gen_random_uuid();
  groups uuid[] := array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
  suffix text := txid_current()::text;
begin
  -- Use the same protected-column fixture authority as other licensing tests.
  insert into plm.licensing_write_authorization
    (backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
  values
    (pg_backend_pid(),txid_current(),'core.licensor','scrape_consolidation',gen_random_uuid(),repeat('4',64),
      'audit-count-contract',array['name','code','status'],clock_timestamp()+interval '1 minute'),
    (pg_backend_pid(),txid_current(),'core.property','scrape_consolidation',gen_random_uuid(),repeat('5',64),
      'audit-count-contract',array['licensor_id','name','code','status'],clock_timestamp()+interval '1 minute');
  insert into core.licensor(id,name,code,status)
  values(lic,'Synthetic audit taxonomy '||suffix,'ZZAC-L-'||suffix,'active');
  insert into core.property(id,licensor_id,name,code,status)
  values(prop,lic,'Synthetic audit property '||suffix,'ZZAC-P-'||suffix,'potential');
  insert into core.customer(id,name,status)
  values(ca,'Synthetic audit customer A '||suffix,'active'),(cb,'Synthetic audit customer B '||suffix,'active');

  -- In particular, the old nondeleted asset has no preview. Legacy taxonomy
  -- counts intentionally have no Library visibility/date/preview predicate.
  insert into public.assets
    (filename,relative_path,file_type,quick_hash,modified_at,file_created_at,thumbnail_url,is_deleted,licensor_id,property_id)
  values
    ('audit-recent.png','ZZAC-'||suffix||'/recent.png','png','zzac-r-'||suffix,now(),now(),'https://example.invalid/audit.png',false,lic,prop),
    ('audit-old.png','ZZAC-'||suffix||'/old.png','png','zzac-o-'||suffix,'1999-01-01','1999-01-01',null,false,lic,prop),
    ('audit-deleted.png','ZZAC-'||suffix||'/deleted.png','png','zzac-d-'||suffix,now(),now(),'https://example.invalid/deleted.png',true,lic,prop);

  insert into public.style_groups(id,sku,folder_path)
  select groups[n],'ZZAC-'||suffix||'-'||n,'ZZAC-'||suffix||case when n=1 then '/WALL ART/needle' else '/group-'||n end
  from generate_series(1,5) n;
  update public.style_groups g set
    asset_count=v.n,latest_file_date=v.file_date,is_licensed=v.licensed,
    customer_id=v.customer,program=v.program,product_category=v.category,
    primary_thumbnail_url=v.preview,primary_thumbnail_error=v.error
  from (values
    (groups[1],3,now(),true,ca,'Audit Alpha','Tabletop','https://example.invalid/audit.png',null::text),
    (groups[2],5,now(),false,cb,'Audit Beta','Tabletop',null,null),
    (groups[3],7,'1999-01-01'::timestamptz,true,ca,'Audit Alpha','Wall',null,'no_pdf_compat'),
    (groups[4],11,null::timestamptz,true,ca,'Audit Alpha','Storage',null,'unsupported_format'),
    (groups[5],0,null::timestamptz,true,ca,'Audit Alpha','Wall',null,null)
  ) v(id,n,file_date,licensed,customer,program,category,preview,error)
  where g.id=v.id;

  -- Follow the ordinary invitation-only signup path; both signup triggers stay enabled.
  insert into public.invitations(email)
  values('audit-count-entitled-'||suffix||'@example.invalid'),
    ('audit-count-denied-'||suffix||'@example.invalid');
  insert into auth.users(id,email)
  values(entitled,'audit-count-entitled-'||suffix||'@example.invalid'),(denied,'audit-count-denied-'||suffix||'@example.invalid');
  insert into app.profile(auth_user_id,email,display_name,status)
  values(entitled,'audit-count-entitled-'||suffix||'@example.invalid','Synthetic count reader','active'),
    (denied,'audit-count-denied-'||suffix||'@example.invalid','Synthetic denied reader','active')
  on conflict(auth_user_id) do update set status='active';
  insert into app.app_access(profile_id,app)
  select id,'dam'::app.app_name from app.profile where auth_user_id=entitled;
  perform set_config('audit_count.fixture',jsonb_build_object('lic',lic,'prop',prop,'customer',ca,
    'groups',to_jsonb(groups),'entitled',entitled,'denied',denied)::text,true);
end;
$fixtures$;

-- Exercise the normal signed-in DAM reader, without administrator/service role.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated',
  'sub',(current_setting('audit_count.fixture')::jsonb->>'entitled'))::text,true);
select set_config('request.jwt.claim.sub',current_setting('audit_count.fixture')::jsonb->>'entitled',true);
select set_config('request.jwt.claim.role','authenticated',true);
do $positive$
declare
  f jsonb := current_setting('audit_count.fixture')::jsonb;
  ids uuid[] := array(select jsonb_array_elements_text(f->'groups')::uuid);
  counts jsonb; actual bigint; expected bigint; filters jsonb; terms text[];
begin
  if not app.has_app_access('dam'::app.app_name) or app.has_role('administrator') then
    raise exception 'fixture must be an ordinary DAM-entitled identity';
  end if;
  counts:=public.get_dam_asset_taxonomy_counts();
  if counts #> array['licensors',f->>'lic'] is distinct from '2'::jsonb
    or counts #> array['properties',f->>'prop'] is distinct from '2'::jsonb then
    raise exception 'taxonomy must count recent plus old/no-preview rows, excluding deleted rows: %',counts;
  end if;
  for filters,expected in select * from (values
    ('{}'::jsonb,19::bigint),
    (jsonb_build_object('customer',f->>'customer'),14),
    ('{"program":"Audit Alpha"}'::jsonb,14),
    ('{"program":"Audit Beta"}'::jsonb,5),
    ('{"isLicensed":true}'::jsonb,14),
    ('{"isLicensed":false}'::jsonb,5),
    ('{"fileStatus":["has_preview"]}'::jsonb,3),
    ('{"fileStatus":["no_preview_renderable"]}'::jsonb,5),
    ('{"fileStatus":["no_pdf_compat"]}'::jsonb,0),
    ('{"fileStatus":["no_preview_unsupported"]}'::jsonb,11),
    ('{"productCategory":["Tabletop"]}'::jsonb,8),
    ('{"productCategory":["Wall"]}'::jsonb,3),
    ('{"productCategory":["Storage"]}'::jsonb,11),
    ('{"productCategory":["unknown-category"]}'::jsonb,19),
    ('{"productCategory":[" Wall "]}'::jsonb,3),
    ('{"productCategory":[" Wall ","Storage"]}'::jsonb,14),
    ('{"productCategory":["Wall","unknown-category","Wall"]}'::jsonb,3),
    ('{"productCategory":["wall"]}'::jsonb,19),
    (jsonb_build_object('productCategory',jsonb_build_array(E'\tWall\n')),3),
    (jsonb_build_object('productCategory',jsonb_build_array(chr(160)||'Wall'||chr(160))),3),
    (jsonb_build_object('productCategory',jsonb_build_array(chr(65279)||'Storage'||chr(65279))),11),
    (jsonb_build_object('customerId',gen_random_uuid()),19),
    (jsonb_build_object('customer',f->>'customer','program','Audit Alpha','isLicensed',true,
      'fileStatus',jsonb_build_array('has_preview'),'productCategory',jsonb_build_array('Wall')),3)
  ) cases(filters,expected) loop
    actual:=public.get_dam_style_group_asset_count(filters,'2020-01-01',ids,null);
    if actual<>expected then raise exception 'group filter % expected %, got %',filters,expected,actual; end if;
  end loop;
  -- Date gates, null-date positive counts, and explicit empty ranked IDs.
  if public.get_dam_style_group_asset_count('{}','1990-01-01',ids,null)<>26
    or public.get_dam_style_group_asset_count('{}','2100-01-01',ids,null)<>11
    or public.get_dam_style_group_asset_count('{}','2020-01-01',array[]::uuid[],null)<>0
    or public.get_dam_style_group_asset_count('{"fileStatus":["no_pdf_compat"]}','1990-01-01',ids,null)<>7 then
    raise exception 'group date/empty-ID boundary differs';
  end if;
  for terms,expected in select * from (values
    (array['needle']::text[],3::bigint),(array['Audit Beta'],5),
    (array['not-a-match','Audit Beta'],5),(array['no-match'],0),(array[]::text[],0)
  ) cases(terms,expected) loop
    actual:=public.get_dam_style_group_asset_count('{}','2020-01-01',ids,terms);
    if actual<>expected then raise exception 'fallback expected %, got %',expected,actual; end if;
  end loop;
end;
$positive$;

-- A real signed-in but unentitled fixture must not receive either aggregate.
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated',
  'sub',(current_setting('audit_count.fixture')::jsonb->>'denied'))::text,true);
select set_config('request.jwt.claim.sub',current_setting('audit_count.fixture')::jsonb->>'denied',true);
do $denied$
begin
  if app.has_app_access('dam'::app.app_name) then raise exception 'denied fixture unexpectedly entitled'; end if;
  begin perform public.get_dam_asset_taxonomy_counts(); raise exception 'denied taxonomy accepted';
  exception when insufficient_privilege then null; end;
  begin perform public.get_dam_style_group_asset_count(); raise exception 'denied group count accepted';
  exception when insufficient_privilege then null; end;
end;
$denied$;
reset role;

-- Verify both the catalog grant and actual anonymous invocation denial.
do $grants$
begin
  if has_function_privilege('anon','public.get_dam_asset_taxonomy_counts()','execute')
    or has_function_privilege('anon','public.get_dam_style_group_asset_count(jsonb,timestamptz,uuid[],text[])','execute') then
    raise exception 'anonymous aggregate execution grant leaked';
  end if;
end;
$grants$;
set local role anon;
do $anonymous$
begin
  begin perform public.get_dam_asset_taxonomy_counts(); raise exception 'anonymous taxonomy accepted';
  exception when insufficient_privilege then null; end;
  begin perform public.get_dam_style_group_asset_count(); raise exception 'anonymous group count accepted';
  exception when insufficient_privilege then null; end;
end;
$anonymous$;
rollback;
