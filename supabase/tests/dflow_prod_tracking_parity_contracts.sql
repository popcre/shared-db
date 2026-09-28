-- Issue #2875: dflow_prod carries the complete current DesignFlow Tracking
-- sample surface, definitionally identical to canonical dflow apart from the
-- schema name, with no reference back to dflow and no copied rows.
begin;

create temporary table t2875_rel(name text primary key) on commit drop;
insert into t2875_rel values ('sample_approval_event'), ('sample_approval_current'), ('sample_balance_by_location'), ('sample_carrier'), ('sample_creation_batch'), ('sample_factory_visit'), ('sample_factory_visit_event'), ('sample_global_status'), ('sample_import_job'), ('sample_import_row'), ('sample_inventory_balance'), ('sample_inventory'), ('sample_in_transit'), ('sample_movement'), ('sample_open_stop_work'), ('sample_path_revision'), ('sample_piece_lineage'), ('sample_receipt_discrepancy'), ('sample_remote_request'), ('sample_remote_request_history'), ('sample_remote_request_item'), ('sample_reservation'), ('sample_shipment'), ('sample_shipment_line'), ('sample_stop_closeout'), ('sample_visit_plan'), ('sample_workflow');
create temporary table t2875_fn(name text primary key) on commit drop;
insert into t2875_fn values ('apply_sample_factory_visit_event'), ('apply_sample_path_revision'), ('pack_sample_reservation'), ('post_sample_approval_event'), ('post_sample_movement'), ('post_sample_piece_split'), ('post_sample_remote_request_event'), ('prevent_sample_shipment_route_drift'), ('project_sample_inventory_movement'), ('reject_sample_approval_event_mutation'), ('reject_sample_factory_visit_event_mutation'), ('reject_sample_movement_mutation'), ('reject_sample_path_revision_mutation'), ('require_sample_factory_visit_event'), ('require_sample_path_revision'), ('reserve_sample_remote_request_item'), ('sample_movement_auto_office_inventory'), ('sample_movement_guard'), ('touch_sample_factory_visit_updated_at'), ('validate_sample_approval_event'), ('validate_sample_factory_visit'), ('validate_sample_factory_visit_event'), ('validate_sample_movement_shipment_identity'), ('validate_sample_path_revision'), ('validate_sample_piece_lineage'), ('validate_sample_shipment_line_header');

-- Tracking items added to tables that already existed in dflow_prod.
create temporary table t2875_delta(item text primary key) on commit drop;
insert into t2875_delta values
  ('sample.quantity_migration_state'), ('sample_box.owner_factory_id_fk'),
  ('sample_box.ownership_state'), ('sample_box.current_custody_type'),
  ('sample_box.current_custody_id'), ('sample_shipment_item.quantity_intended'),
  ('sample.sample_quantity_migration_state_check'), ('sample_box.sample_box_custody_pair_check'),
  ('sample_box.sample_box_ownership_state_check'), ('sample_box.sample_box_owner_factory_fkey'),
  ('sample_shipment_item.sample_shipment_item_quantity_positive'),
  ('sample_shipment_item.sample_shipment_item_sample_box_uniq'),
  ('sample.sample_quantity_migration_state_idx'), ('sample_box.sample_box_active_name_custody_uniq'),
  ('sample_box.sample_box_owner_factory_idx'), ('sample_shipment_item.sample_shipment_item_box_id_fk_idx'),
  ('sample_shipment_item.sample_shipment_item_sample_id_fk_idx');

create temporary view t2875_all as
with rel as (
  select n.nspname s, c.oid, c.relname, c.relkind
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('dflow', 'dflow_prod')
    and (c.relname in (select name from t2875_rel)
         or c.relname in ('sample', 'sample_box', 'sample_shipment_item'))
), fn as (
  select n.nspname s, p.oid, p.proname
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('dflow', 'dflow_prod') and p.proname in (select name from t2875_fn)
)
select s, 'relation' k, relname nm, relkind::text || ' acl=' || coalesce((select relacl::text from pg_class where oid = rel.oid), '-')
       || ' rls=' || (select relrowsecurity::text from pg_class where oid = rel.oid)
       || ' opts=' || coalesce((select reloptions::text from pg_class where oid = rel.oid), '-')
       || ' cmt=' || coalesce(obj_description(oid, 'pg_class'), '-') d
from rel where relname in (select name from t2875_rel)
union all
select r.s, 'column', r.relname || '.' || a.attname,
       format_type(a.atttypid, a.atttypmod) || ' nn=' || a.attnotnull || ' id=' || a.attidentity::text || ' gen=' || a.attgenerated::text
       || ' def=' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-') || ' acl=' || coalesce(a.attacl::text, '-')
       || ' cmt=' || coalesce(col_description(r.oid, a.attnum), '-')
from rel r join pg_attribute a on a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped
left join pg_attrdef d on d.adrelid = r.oid and d.adnum = a.attnum
where r.relkind in ('r', 'v')
union all
select r.s, 'constraint', r.relname || '.' || co.conname,
       pg_get_constraintdef(co.oid) || ' cmt=' || coalesce(obj_description(co.oid, 'pg_constraint'), '-')
from rel r join pg_constraint co on co.conrelid = r.oid and co.contype <> 'n'
union all
select r.s, 'index', r.relname || '.' || i.relname,
       pg_get_indexdef(i.oid) || ' cmt=' || coalesce(obj_description(i.oid, 'pg_class'), '-')
from rel r join pg_index x on x.indrelid = r.oid join pg_class i on i.oid = x.indexrelid
union all
select r.s, 'trigger', r.relname || '.' || t.tgname,
       pg_get_triggerdef(t.oid) || ' en=' || t.tgenabled::text || ' cmt=' || coalesce(obj_description(t.oid, 'pg_trigger'), '-')
from rel r join pg_trigger t on t.tgrelid = r.oid and not t.tgisinternal
union all
select r.s, 'view', r.relname, pg_get_viewdef(r.oid)
from rel r where r.relkind = 'v'
union all
select f.s, 'function', f.proname || '(' || pg_get_function_identity_arguments(f.oid) || ')',
       pg_get_functiondef(f.oid) || ' acl=' || coalesce((select proacl::text from pg_proc where oid = f.oid), '-')
       || ' cmt=' || coalesce(obj_description(f.oid, 'pg_proc'), '-')
from fn f;

create temporary view t2875_def as
select * from t2875_all
where k in ('relation', 'view', 'function')
   or split_part(nm, '.', 1) in (select name from t2875_rel)
   or nm in (select item from t2875_delta);

do $test$
declare
  v_missing text;
  v_extra text;
  v_count integer;
begin
  -- Every expected object exists in dflow_prod.
  select string_agg(name, ', ') into v_missing from t2875_rel
  where to_regclass('dflow_prod.' || name) is null;
  if v_missing is not null then raise exception '#2875 missing dflow_prod relations: %', v_missing; end if;
  select string_agg(name, ', ') into v_missing from t2875_fn f
  where not exists (select 1 from pg_proc p where p.pronamespace = 'dflow_prod'::regnamespace and p.proname = f.name);
  if v_missing is not null then raise exception '#2875 missing dflow_prod functions: %', v_missing; end if;

  -- Definitional parity: every dflow definition has an identical dflow_prod twin
  -- once the schema name is normalised, and dflow_prod has nothing extra.
  select string_agg(k || ' ' || nm, ', ' order by k, nm) into v_missing
  from (select k, nm, replace(replace(d, 'dflow.', 'dflow_prod.'), '''dflow''', '''dflow_prod''') d from t2875_def where s = 'dflow'
        except select k, nm, d from t2875_def where s = 'dflow_prod') x;
  if v_missing is not null then
    raise exception '#2875 dflow_prod differs from canonical dflow (missing or different): %', v_missing;
  end if;
  select string_agg(k || ' ' || nm, ', ' order by k, nm) into v_extra
  from (select k, nm, d from t2875_def where s = 'dflow_prod'
        except select k, nm, replace(replace(d, 'dflow.', 'dflow_prod.'), '''dflow''', '''dflow_prod''') from t2875_def where s = 'dflow') x;
  if v_extra is not null then
    raise exception '#2875 dflow_prod has Tracking definitions canonical dflow lacks: %', v_extra;
  end if;

  -- Nothing in the new surface refers back to dflow.
  if exists (select 1 from t2875_def where s = 'dflow_prod'
             and d ~ '(^|[^A-Za-z0-9_."])dflow\.') then
    raise exception '#2875 a dflow_prod Tracking object references schema dflow';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'dflow_prod'::regnamespace
             and p.proname in (select name from t2875_fn)
             and array_to_string(p.proconfig, ',') ~ '(^|[=, ])dflow($|,)') then
    raise exception '#2875 a dflow_prod Tracking function pins search_path to dflow';
  end if;

  -- No application rows copied: only the four canonical carrier rows exist.
  select count(*) into v_count from dflow_prod.sample_movement;
  if v_count <> 0 then raise exception '#2875 dflow_prod.sample_movement must start empty, found %', v_count; end if;
  select count(*) into v_count from dflow_prod.sample_carrier;
  if v_count <> 4 then raise exception '#2875 expected exactly 4 canonical carriers, found %', v_count; end if;
end
$test$;

rollback;
