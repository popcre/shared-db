-- Contract tests for 20261018191107_plm_stage_catalog_prod_tracking_grant.sql
-- (issue #4464, claim #4467). Run by .github/workflows/database-contract-tests.yml
-- inside begin; ... rollback; as the migration owner. No fixture rows are kept.
--
-- A. Catalogue: exact privilege matrix, no CREATE on plm, no new anon/authenticated
--    privilege, RLS still enabled, each policy targets only the tracking grant role.
-- B. Behaviour (only when the session already holds the role): as designflow_prod_tracking_grants, the seeded catalog is visible,
--    an editor write succeeds and bumps the list version, and progress writes are
--    refused at the privilege level.

do $a$
declare v_bad text; v_n int;
begin
  select string_agg(t || ':' || p, ', ') into v_bad
  from unnest(array['stage_list','stage','stage_duration','stage_dependency','licensor_stage_option','prod_stage_progress','prod_stage_option']) t
  cross join unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p
  where has_table_privilege('designflow_prod_tracking_grants', 'plm.' || t, p)
        is distinct from (p = 'SELECT' or (p <> 'TRUNCATE' and t not in ('prod_stage_progress','prod_stage_option')));
  if v_bad is not null then raise exception 'A1 privilege matrix differs: %', v_bad; end if;
  if not has_schema_privilege('designflow_prod_tracking_grants', 'plm', 'USAGE') then raise exception 'A2 no USAGE'; end if;
  if has_schema_privilege('designflow_prod_tracking_grants', 'plm', 'CREATE') then raise exception 'A3 CREATE granted'; end if;
  select count(*) into v_n from unnest(array['anon','authenticated']) r
    cross join unnest(array['stage_list','stage','stage_duration','stage_dependency','licensor_stage_option','prod_stage_progress','prod_stage_option']) t
    where has_table_privilege(r, 'plm.' || t, 'SELECT');
  if v_n <> 0 then raise exception 'A4 client roles can read the catalog (%)', v_n; end if;
  select count(*) into v_n from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'plm' and c.relname in ('stage_list','stage','stage_duration','stage_dependency','licensor_stage_option','prod_stage_progress','prod_stage_option') and c.relrowsecurity;
  if v_n <> 7 then raise exception 'A5 RLS disabled on % tables', 7 - v_n; end if;
  select count(*) into v_n from pg_policies
    where schemaname = 'plm' and policyname like '%dflow_prod_tracking%' and roles = array['designflow_prod_tracking_grants']::name[];
  if v_n <> 7 then raise exception 'A6 expected 7 role-scoped policies, found %', v_n; end if;
  select count(*) into v_n from pg_policies
    where schemaname = 'plm' and policyname like '%dflow_prod_tracking_read' and cmd <> 'SELECT';
  if v_n <> 0 then raise exception 'A7 read policies allow writes'; end if;
  select count(*) into v_n from pg_policies
    where schemaname = 'plm' and policyname like '%dflow_prod_tracking%'
      and (qual is distinct from 'true' or (cmd = 'ALL' and with_check is distinct from 'true') or permissive <> 'PERMISSIVE');
  if v_n <> 0 then raise exception 'A8 policy predicates differ from true'; end if;
end
$a$;

-- Behaviour runs only where the test session already holds the grant role. A test must
-- not grant itself role membership: on the CI stack that GRANT terminated the server.
do $b$
declare v_lists int; v_stages int; v_before int; v_after int; v_id int; v_denied boolean := false;
begin
  if not pg_has_role(current_user, 'designflow_prod_tracking_grants', 'MEMBER') then
    raise notice 'B skipped: % is not a member of designflow_prod_tracking_grants', current_user;
    return;
  end if;
  set local role designflow_prod_tracking_grants;
  select count(*) into v_lists from plm.stage_list;
  select count(*) into v_stages from plm.stage;
  if v_lists = 0 or v_stages = 0 then raise exception 'B1 catalog invisible to tracking role (lists %, stages %)', v_lists, v_stages; end if;
  perform count(*) from plm.stage_duration;
  perform count(*) from plm.licensor_stage_option;
  perform count(*) from plm.prod_stage_progress;
  perform count(*) from plm.prod_stage_option;
  select s.id, l.version into v_id, v_before from plm.stage s join plm.stage_list l on l.id = s.list_id order by s.id limit 1;
  update plm.stage set updated_by = updated_by where id = v_id;
  select l.version into v_after from plm.stage s join plm.stage_list l on l.id = s.list_id where s.id = v_id;
  if v_after <> v_before + 1 then raise exception 'B2 editor write did not bump version (% -> %)', v_before, v_after; end if;
  begin
    insert into plm.prod_stage_option (prod_order_header_id, needs_linesheet) values (-4464, true);
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'B3 prod_stage_option write was not refused'; end if;
  reset role;
end
$b$;
