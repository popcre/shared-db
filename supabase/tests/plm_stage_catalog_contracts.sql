begin;

-- shared-db#4350 (claim #4355): Stage Catalog seed counts, browser-role denial,
-- constraints and the version trigger. Rolled back.
do $$
declare
  v_list integer;
  v_stage integer;
  v_before integer;
  v_after integer;
begin
  if (select count(*) from plm.stage_list) <> 5
     or (select count(*) from plm.stage) <> 24
     or (select count(*) from plm.stage_duration) <> 637
     or (select count(*) from plm.licensor_stage_option where enabled) <> 16
     or (select count(*) from plm.licensor_stage_option) <> 32
     or (select count(*) from plm.stage_dependency) <> 0
     or (select count(*) from plm.prod_stage_progress) <> 0
     or (select count(*) from plm.stage where shown_on_tracker) <> 12 then
    raise exception 'stage catalog seed counts are wrong';
  end if;
  if exists (select 1 from plm.stage_list where version <> 1) then
    raise exception 'seeded lists must start at version 1';
  end if;
  if (select maintainers from plm.stage_list where key = 'sampling') <> '{36,41}'::integer[] then
    raise exception 'sampling maintainers must be Yuchen (36) and Ilona (41)';
  end if;

  if (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'plm' and c.relrowsecurity
         and c.relname in ('stage_list','stage','stage_duration','stage_dependency',
                           'licensor_stage_option','prod_stage_progress')) <> 6 then
    raise exception 'all six stage catalog tables must have RLS enabled';
  end if;
  if exists (select 1 from pg_roles r cross join unnest(array['plm.stage_list','plm.stage',
               'plm.stage_duration','plm.stage_dependency','plm.licensor_stage_option',
               'plm.prod_stage_progress']) t(name)
             where r.rolname in ('anon','authenticated')
               and (has_table_privilege(r.rolname, t.name, 'select')
                    or has_table_privilege(r.rolname, t.name, 'insert')
                    or has_table_privilege(r.rolname, t.name, 'update')
                    or has_table_privilege(r.rolname, t.name, 'delete'))) then
    raise exception 'browser roles must have no privilege on the stage catalog';
  end if;

  select id into v_list from plm.stage_list where key = 'production';
  select id into v_stage from plm.stage where list_id = v_list and position = 1;
  select version into v_before from plm.stage_list where id = v_list;
  update plm.stage set pending_label = pending_label || ' x' where id = v_stage;
  insert into plm.stage_duration (stage_id, scope_kind, scope_value, duration)
    values (v_stage, 'product_type', 'contract-test', 1);
  insert into plm.stage_dependency (stage_id, depends_on_stage_id, kind)
    select v_stage, id, 'hard' from plm.stage where list_id = v_list and position = 2;
  select version into v_after from plm.stage_list where id = v_list;
  if v_after <> v_before + 3 then
    raise exception 'version must bump once per change (before %, after %)', v_before, v_after;
  end if;
  update plm.stage_list set name = name where id = v_list;
  if (select version from plm.stage_list where id = v_list) <> v_after then
    raise exception 'a no-op list update must not bump the version';
  end if;
  update plm.stage_list set name = name || ' x' where id = v_list;
  if (select version from plm.stage_list where id = v_list) <> v_after + 1 then
    raise exception 'a list edit must bump the version once';
  end if;

  begin
    insert into plm.stage_dependency (stage_id, depends_on_stage_id, kind) values (v_stage, v_stage, 'soft');
    raise exception 'self dependency must be refused';
  exception when check_violation then null;
  end;

  insert into plm.prod_stage_progress (prod_order_header_id, sku, stage_id) values (-1, null, v_stage);
  begin
    insert into plm.prod_stage_progress (prod_order_header_id, sku, stage_id) values (-1, null, v_stage);
    raise exception 'duplicate PO-level progress must be refused';
  exception when unique_violation then null;
  end;
end;
$$;

rollback;
