-- #4427 PARTIAL runtime qualification; ALL catalog identities covered.
-- LOCAL THROWAWAY DATABASE ONLY. Requires the real CI bootstrap and its four .invalid users.
-- Never execute against production. Shared-preview execution requires separate admission.
-- No triggers, grants, helpers, RLS flags, policies or features are disabled.
-- Tested command fixtures: assets INSERT/UPDATE/SELECT; admin_config ALL; profiles SELECT.
-- Other 36 tables: bounded SELECT/error equivalence and catalog union only.
-- This is NOT all-table DML coverage, performance qualification, or live acceptance.
begin;
set local statement_timeout = '20s';
set local lock_timeout = '3s';

create temp table rls4427_manifest (
 schema_name text, table_name text, policy_name text, command text,
 original_using text, original_check text, primary key(schema_name,table_name,policy_name)
) on commit drop;
insert into rls4427_manifest values
('archive','erp_items_current','Admin manage erp_items_current','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('archive','erp_items_raw','Admin manage erp_items_raw','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('plm','legacy_erp_item_identity','legacy_erp_item_identity_admin_read','r','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','admin_config','Admin delete admin_config','d','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','admin_config','Admin read all admin_config','r','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','admin_config','Admin update admin_config','w','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','admin_config','Admin write admin_config','a',NULL,'has_role(auth.uid(), ''admin''::app_role)'),
('public','agent_pairings','Admin manage agent_pairings','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','agent_registrations','Admin manage agent_registrations','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','ai_tag_bakeoff_results','Admin manage ai tag bakeoff results','*','has_role(auth.uid(), ''admin''::app_role)','has_role(auth.uid(), ''admin''::app_role)'),
('public','ai_tag_bakeoff_results','Admin read ai tag bakeoff results','r','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','ai_tag_bakeoff_reviews','Admin manage ai tag bakeoff reviews','*','has_role(auth.uid(), ''admin''::app_role)','has_role(auth.uid(), ''admin''::app_role)'),
('public','ai_tag_bakeoff_reviews','Admin read ai tag bakeoff reviews','r','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','ai_tag_bakeoff_runs','Admin manage ai tag bakeoff runs','*','has_role(auth.uid(), ''admin''::app_role)','has_role(auth.uid(), ''admin''::app_role)'),
('public','ai_tag_bakeoff_runs','Admin read ai tag bakeoff runs','r','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','app_access','Admins manage app_access','*','has_role(auth.uid(), ''admin''::app_role)','has_role(auth.uid(), ''admin''::app_role)'),
('public','asset_characters','Admin write asset_characters','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','asset_tags','Admin manage asset_tags','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','assets','Admins can insert assets','a',NULL,'has_role(auth.uid(), ''admin''::app_role)'),
('public','assets','Admins can update assets','w','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','characters','Admin write characters','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','erp_enrichment_log','Admin manage erp_enrichment_log','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','erp_sync_runs','Admin manage erp_sync_runs','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','hygiene_findings','Admin manage hygiene_findings','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','invitations','Admin manage invitations','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','licensors','Admin write licensors','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','pdf_text_samples','admin full access pdf_text_samples','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','processing_queue','Admin manage processing_queue','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','prod_order_headers_current','Admins manage prod_order_headers_current','*','has_role(auth.uid(), ''admin''::app_role)','has_role(auth.uid(), ''admin''::app_role)'),
('public','prod_order_headers_raw','Admins manage prod_order_headers_raw','*','has_role(auth.uid(), ''admin''::app_role)','has_role(auth.uid(), ''admin''::app_role)'),
('public','prod_order_sync_runs','Admins manage prod_order_sync_runs','*','has_role(auth.uid(), ''admin''::app_role)','has_role(auth.uid(), ''admin''::app_role)'),
('public','product_categories','Admin write product_categories','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','product_category_predictions','Admin manage product_category_predictions','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','product_subtypes','Admin write product_subtypes','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','product_types','Admin write product_types','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','profiles','Admins read all profiles','r','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','properties','Admin write properties','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','render_queue','Admin manage render_queue','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','style_group_tags','Admin manage style_group_tags','*','has_role(auth.uid(), ''admin''::app_role)','has_role(auth.uid(), ''admin''::app_role)'),
('public','style_groups','Admins can manage style_groups','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','style_guide_crawl_runs','admin full access style_guide_crawl_runs','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','style_guide_files','admin full access style_guide_files','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','style_guide_render_queue','Admin manage style_guide_render_queue','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','style_tracker_rows','Admins delete style tracker rows','d','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','tiff_optimization_queue','Admin manage tiff_optimization_queue','*','has_role(auth.uid(), ''admin''::app_role)',NULL),
('public','user_roles','Admins manage user_roles','*','has_role(auth.uid(), ''admin''::app_role)',NULL);

create temp table rls4427_relations on commit drop as
select distinct c.oid, n.nspname, c.relname
from rls4427_manifest m join pg_namespace n on n.nspname=m.schema_name
join pg_class c on c.relnamespace=n.oid and c.relname=m.table_name;

-- Preserve every overlapping policy, not only the 46 optimized expressions.
create temp table rls4427_candidate_policies on commit drop as
select p.*, pg_get_expr(p.polqual,p.polrelid) as qual_text,
 pg_get_expr(p.polwithcheck,p.polrelid) as check_text
from pg_policy p join rls4427_relations r on r.oid=p.polrelid;

create temp table rls4427_catalog_before on commit drop as
select jsonb_build_object(
 'tables',(select jsonb_agg(jsonb_build_object('oid',c.oid,'owner',c.relowner,
  'acl',c.relacl::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
  'column_acls',(select jsonb_agg(jsonb_build_array(a.attnum,a.attacl::text)
   order by a.attnum) from pg_attribute a where a.attrelid=c.oid and a.attnum>0
   and not a.attisdropped)) order by c.oid)
  from pg_class c join rls4427_relations r on r.oid=c.oid),
 'helpers',(select jsonb_agg(jsonb_build_object('oid',p.oid,'owner',p.proowner,
  'acl',p.proacl::text,'volatility',p.provolatile,'definer',p.prosecdef,
  'config',p.proconfig,'body',pg_get_functiondef(p.oid)) order by p.oid)
  from pg_proc p where p.oid in ('public.has_role(uuid,public.app_role)'::regprocedure,
  'auth.uid()'::regprocedure)),
 'role_type',(select jsonb_build_array(t.oid,t.typowner,t.typacl::text)
  from pg_type t where t.oid='public.app_role'::regtype)
) as snapshot;

do $qualification$
declare v_n integer;
begin
 if (select count(*) from rls4427_manifest)<>46 or
    (select count(*) from rls4427_relations)<>39 then
  raise exception '4427 manifest lost exact 46-policy/39-table coverage';
 end if;
 select count(*) into v_n from rls4427_manifest m join pg_namespace n
 on n.nspname=m.schema_name join pg_class c on c.relnamespace=n.oid and c.relname=m.table_name
 join pg_policy p on p.polrelid=c.oid and p.polname=m.policy_name;
 if v_n<>46 then raise exception '4427 exact policy identity missing'; end if;
 if (select count(*) from rls4427_candidate_policies)<>72 then
  raise exception '4427 applicable policy union drift; require refreshed reviewed manifest';
 end if;
 if exists(select 1 from rls4427_manifest m join pg_namespace n on n.nspname=m.schema_name
 join pg_class c on c.relnamespace=n.oid and c.relname=m.table_name
 join pg_policy p on p.polrelid=c.oid and p.polname=m.policy_name
 where p.polcmd::text<>m.command or
 ((p.polqual is null)<>(m.original_using is null)) or
 ((p.polwithcheck is null)<>(m.original_check is null)) or
 (m.original_using is not null and position('SELECT' in upper(pg_get_expr(p.polqual,p.polrelid)))=0) or
 (m.original_check is not null and position('SELECT' in upper(pg_get_expr(p.polwithcheck,p.polrelid)))=0)) then
  raise exception '4427 candidate command/null-check/scalar-select contract violated';
 end if;
 -- Genuine existing synthetic seed, not a forged auth metadata provider or disabled trigger.
 if (select count(*) from auth.users where id in
 ('00000000-7541-4000-8000-000000000001'::uuid,
  '00000000-7541-4000-8000-000000000002'::uuid)
 and email in ('zz-fixture-user-1@fixture.invalid','zz-fixture-user-2@fixture.invalid'))<>2 then
  raise exception '4427 requires CI synthetic bootstrap users; do not run on shared production';
 end if;
 if exists(select 1 from rls4427_relations r join pg_class c on c.oid=r.oid
 where c.relowner in ('authenticated'::regrole,'anon'::regrole)) then
  raise exception '4427 non-bypass roles own target table';
 end if;
end $qualification$;

-- Rollback-contained setup. The original production grant and policy model stays active.
insert into public.user_roles(user_id,role)
select '00000000-7541-4000-8000-000000000001'::uuid,'admin'::public.app_role
where not exists(select 1 from public.user_roles
 where user_id='00000000-7541-4000-8000-000000000001'::uuid and role='admin');
delete from public.user_roles where
 user_id='00000000-7541-4000-8000-000000000002'::uuid and role='admin';

-- Front-door auth provisioning should already have made these public profiles.
insert into public.profiles(user_id,email)
select a.id,a.email from auth.users a where a.id in
 ('00000000-7541-4000-8000-000000000001'::uuid,
  '00000000-7541-4000-8000-000000000002'::uuid)
and not exists(select 1 from public.profiles p where p.user_id=a.id);

insert into public.admin_config(key,value) values('zz_rls4427_secret_probe','{"synthetic":true}'::jsonb);
insert into public.assets(id,filename,relative_path,file_type,quick_hash,modified_at,style_group_id,thumbnail_error)
values('44270000-0000-4000-8000-000000000001','zz-rls4427-probe.ai',
 'zz-fixture-rls4427/zz-rls4427-probe.ai','ai','zz-rls4427-synthetic-probe',now(),null,null);

-- Invoker-only probing, with each write reverted by a private subtransaction.
-- Variables survive the exception rollback; rows and trigger effects do not.
create function pg_temp.rls4427_probe(statement_text text) returns jsonb
language plpgsql security invoker as $probe$
declare v_result jsonb; v_state text;
begin
 begin
  execute statement_text into v_result;
  v_state:='00000';
  raise exception using errcode='Z4427',message='rollback one synthetic probe';
 exception
  when sqlstate 'Z4427' then null;
  when others then get stacked diagnostics v_state=returned_sqlstate; v_result:=null;
 end;
 return jsonb_build_object('sqlstate',v_state,'result',v_result);
end $probe$;

create temp table rls4427_cases(name text primary key,statement_text text) on commit drop;
insert into rls4427_cases values
('profile_ownership_union', $q$select jsonb_build_object('labels',coalesce(jsonb_agg(case user_id
 when '00000000-7541-4000-8000-000000000001'::uuid then 'admin_fixture'
 else 'member_fixture' end order by user_id),'[]'::jsonb)) from public.profiles
 where user_id in('00000000-7541-4000-8000-000000000001'::uuid,
 '00000000-7541-4000-8000-000000000002'::uuid)$q$),
('config_privileged_read',$q$select jsonb_build_object('count',count(*)) from public.admin_config
 where key='zz_rls4427_secret_probe'$q$),
('asset_visible_read',$q$select jsonb_build_object('count',count(*)) from public.assets
 where id='44270000-0000-4000-8000-000000000001'::uuid$q$),
('asset_insert',$q$with changed as (insert into public.assets(id,filename,relative_path,file_type,quick_hash,modified_at)
 values('44270000-0000-4000-8000-000000000002','zz-rls4427-insert.ai',
 'zz-fixture-rls4427/zz-rls4427-insert.ai','ai','zz-rls4427-synthetic-insert',now()) returning id)
 select jsonb_build_object('count',count(*)) from changed$q$),
('asset_update',$q$with changed as (update public.assets set workflow_status='other'
 where id='44270000-0000-4000-8000-000000000001'::uuid returning id)
 select jsonb_build_object('count',count(*)) from changed$q$),
('config_insert',$q$with changed as (insert into public.admin_config(key,value)
 values('zz_rls4427_secret_insert','{}'::jsonb) returning key)
 select jsonb_build_object('count',count(*)) from changed$q$),
('config_update',$q$with changed as (update public.admin_config set value='{"changed":true}'::jsonb
 where key='zz_rls4427_secret_probe' returning key)
 select jsonb_build_object('count',count(*)) from changed$q$),
('config_delete',$q$with changed as (delete from public.admin_config
 where key='zz_rls4427_secret_probe' returning key)
 select jsonb_build_object('count',count(*)) from changed$q$),
('helper_result',$q$select jsonb_build_object('is_admin',public.has_role(auth.uid(),'admin'::public.app_role))$q$);

-- Bounded reads across the whole table set are useful equality/error probes, but
-- empty tables and other permissive policies can mask admin predicate execution.
insert into rls4427_cases
select 'bounded_read:'||nspname||'.'||relname,
 format('select jsonb_build_object(''count'',count(*)) from(select 1 from %I.%I limit 1) bounded',nspname,relname)
from rls4427_relations;
create temp table rls4427_results(phase text,context text,probe text,result jsonb,
 primary key(phase,context,probe)) on commit drop;

-- All fixture statements are trusted static strings above; execute as caller.
grant select on rls4427_cases to authenticated,anon;
grant execute on function pg_temp.rls4427_probe(text) to authenticated,anon;

-- A prepared invocation must use request context, not a prior caller's result.
prepare rls4427_prepared as select public.has_role(auth.uid(),'admin'::public.app_role);
prepare rls4427_prepared_policy as select count(*) from public.admin_config where key='zz_rls4427_secret_probe';
set local plan_cache_mode='force_generic_plan';

do $equivalence$
declare v_phase text; v_context text; v_role text; v_subject text;
 v_case record; v_policy record; v_clause text; v_result jsonb; v_admin boolean;
 v_before jsonb; v_after jsonb; v_count bigint;
begin
 foreach v_phase in array array['original','candidate'] loop
  -- ALTER preserves every policy OID, role, command, permissive flag and null check.
  for v_policy in select m.*, c.polrelid,c.polname,c.qual_text,c.check_text
    from rls4427_manifest m join rls4427_candidate_policies c
    on c.polname=m.policy_name and c.polrelid=to_regclass(format('%I.%I',m.schema_name,m.table_name))
  loop
   v_clause:='';
   if v_policy.original_using is not null then
    v_clause:=v_clause||' USING ('||case when v_phase='original' then v_policy.original_using else v_policy.qual_text end||')';
   end if;
   if v_policy.original_check is not null then
    v_clause:=v_clause||' WITH CHECK ('||case when v_phase='original' then v_policy.original_check else v_policy.check_text end||')';
   end if;
   execute format('ALTER POLICY %I ON %I.%I%s',v_policy.policy_name,v_policy.schema_name,v_policy.table_name,v_clause);
  end loop;
  foreach v_context in array array['admin','member','missing_subject','malformed_subject','anon','admin_again'] loop
   v_role:=case when v_context='anon' then 'anon' else 'authenticated' end;
   v_subject:=case when v_context in('admin','admin_again') then '00000000-7541-4000-8000-000000000001'
    when v_context='member' then '00000000-7541-4000-8000-000000000002'
    when v_context='malformed_subject' then 'not-a-uuid' else null end;
   -- auth.uid consults the legacy scalar setting FIRST: clear both representations.
   perform set_config('request.jwt.claim.sub','',true);
   perform set_config('request.jwt.claims',jsonb_strip_nulls(jsonb_build_object('role',v_role,'sub',v_subject))::text,true);
   perform set_config('request.jwt.claim','',true);
   execute format('set local role %I',v_role);
   if current_user<>v_role or exists(select 1 from pg_roles
    where rolname=current_user and (rolsuper or rolbypassrls)) then
    raise exception '4427 role is elevated or bypasses RLS';
   end if;
   -- Fetch each trusted probe while still in the same caller context.
   for v_case in select * from rls4427_cases order by name loop
    v_result:=pg_temp.rls4427_probe(v_case.statement_text);
    execute 'reset role';
    insert into rls4427_results values(v_phase,v_context,v_case.name,v_result);
    execute format('set local role %I',v_role);
   end loop;
   begin
    execute 'execute rls4427_prepared' into v_admin;
    v_result:=jsonb_build_object('sqlstate','00000','result',v_admin);
   exception when others then
    v_result:=jsonb_build_object('sqlstate',sqlstate,'result',null);
   end;
   execute 'reset role';
   insert into rls4427_results values(v_phase,v_context,'prepared_helper',v_result);
   execute format('set local role %I',v_role);
   begin
    execute 'execute rls4427_prepared_policy' into v_count;
    v_result:=jsonb_build_object('sqlstate','00000','result',v_count);
   exception when others then
    v_result:=jsonb_build_object('sqlstate',sqlstate,'result',null);
   end;
   execute 'reset role';
   insert into rls4427_results values(v_phase,v_context,'prepared_policy',v_result);
  end loop;
  -- Next-statement grant/revoke semantics through the real public role table.
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-7541-4000-8000-000000000001"}',true);
  execute 'set local role authenticated';
  execute 'execute rls4427_prepared' into v_admin;
  execute 'reset role';
  if v_admin is distinct from true then raise exception '4427 assigned admin not effective'; end if;
  delete from public.user_roles where user_id='00000000-7541-4000-8000-000000000001'::uuid and role='admin';
  execute 'set local role authenticated';
  execute 'execute rls4427_prepared' into v_admin;
  execute 'reset role';
  if v_admin is distinct from false then raise exception '4427 role revocation invisible next statement'; end if;
  insert into public.user_roles(user_id,role) values('00000000-7541-4000-8000-000000000001','admin');
 end loop;
 -- Compare exact results and exact SQLSTATE, including malformed subject behavior.
 if (select count(*) from rls4427_results)<>600 then raise exception '4427 probe coverage incomplete'; end if;
 if exists(select 1 from (select context,probe,result from rls4427_results where phase='original') b
 full join (select context,probe,result from rls4427_results where phase='candidate') a
 using(context,probe) where b.result is distinct from a.result) then
  raise exception '4427 before/after result or SQLSTATE differs';
 end if;
 if exists(select 1 from rls4427_results where context in('admin','admin_again')
 and probe in('asset_insert','asset_update','config_insert','config_update','config_delete','asset_visible_read','config_privileged_read')
 and (result->>'sqlstate'<>'00000' or result#>>'{result,count}' is distinct from '1')) then
  raise exception '4427 positive administrator fixture did not exercise intended operation';
 end if;
 if exists(select 1 from rls4427_results where context='member'
 and probe in('asset_insert','config_insert') and result->>'sqlstate'<>'42501') then
  raise exception '4427 unassigned member unexpectedly inserted admin-only fixture';
 end if;
 if exists(select 1 from rls4427_results where context='member'
 and probe in('asset_update','config_update','config_delete','config_privileged_read')
 and (result->>'sqlstate'<>'00000' or result#>>'{result,count}' is distinct from '0')) then
  raise exception '4427 unassigned member unexpectedly modified/read privileged fixture';
 end if;
 if exists(select 1 from rls4427_results where context in('admin','admin_again') and probe='profile_ownership_union'
 and result#>'{result,labels}' is distinct from '["admin_fixture","member_fixture"]'::jsonb) then
  raise exception '4427 positive administrator profile union control failed';
 end if;
 if exists(select 1 from rls4427_results where context='malformed_subject' and probe='helper_result'
 and result->>'sqlstate'<>'22P02') then raise exception '4427 malformed UUID error control failed'; end if;
 if exists(select 1 from rls4427_results where context='member' and probe='profile_ownership_union'
 and result#>'{result,labels}' is distinct from '["member_fixture"]'::jsonb) then
  raise exception '4427 overlapping own-profile policy was lost';
 end if;
end $equivalence$;

deallocate rls4427_prepared;
deallocate rls4427_prepared_policy;

-- Candidate policy union, including expressions, must exactly equal its initial snapshot.
do $catalog$
declare v_now jsonb; v_before jsonb;
begin
 if exists(select 1 from rls4427_candidate_policies s full join
 (select p.* from pg_policy p join rls4427_relations r on r.oid=p.polrelid) p
 using(oid) where (s.polname,s.polrelid,s.polcmd,s.polpermissive,s.polroles,s.qual_text,s.check_text)
 is distinct from (p.polname,p.polrelid,p.polcmd,p.polpermissive,p.polroles,pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid))) then
  raise exception '4427 full policy union/identity/roles/implicit check did not restore exactly';
 end if;
 select jsonb_build_object(
 'tables',(select jsonb_agg(jsonb_build_object('oid',c.oid,'owner',c.relowner,
  'acl',c.relacl::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
  'column_acls',(select jsonb_agg(jsonb_build_array(a.attnum,a.attacl::text)
   order by a.attnum) from pg_attribute a where a.attrelid=c.oid and a.attnum>0
   and not a.attisdropped)) order by c.oid)
  from pg_class c join rls4427_relations r on r.oid=c.oid),
 'helpers',(select jsonb_agg(jsonb_build_object('oid',p.oid,'owner',p.proowner,
  'acl',p.proacl::text,'volatility',p.provolatile,'definer',p.prosecdef,
  'config',p.proconfig,'body',pg_get_functiondef(p.oid)) order by p.oid)
  from pg_proc p where p.oid in ('public.has_role(uuid,public.app_role)'::regprocedure,
  'auth.uid()'::regprocedure)),
 'role_type',(select jsonb_build_array(t.oid,t.typowner,t.typacl::text)
  from pg_type t where t.oid='public.app_role'::regtype)) into v_now;
 select snapshot into v_before from rls4427_catalog_before;
 if v_now is distinct from v_before then raise exception '4427 helper/ACL/owner/RLS/type metadata changed'; end if;
 raise notice '4427 PARTIAL fixture equivalence passed: assets INSERT/UPDATE/SELECT; admin_config ALL; profiles SELECT; 39 bounded reads; 72 policy metadata identities. Remaining DML adapters are not covered.';
end $catalog$;

rollback;
