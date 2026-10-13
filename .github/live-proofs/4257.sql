-- #4257 / PopDAM #277: read-only production invariant and preserved-history proof.
with trigger_contract as (
  select count(*) = 1 as passed
  from pg_catalog.pg_trigger t
  where t.tgrelid = 'plm.production_order'::regclass
    and t.tgname = 'production_po_no_reuse'
    and not t.tgisinternal and t.tgenabled = 'O'
    and t.tgtype = 23
    and t.tgfoid = 'plm.guard_production_po_number()'::regprocedure
), function_contract as (
  select prosecdef and proconfig = array['search_path=pg_catalog']
    and position('production_po_no_reuse' in pg_get_functiondef(oid)) > 0
    and position('on conflict (normalized_po) do nothing' in lower(pg_get_functiondef(oid))) > 0
    and position('used_at is null' in pg_get_functiondef(oid)) > 0 as passed
  from pg_catalog.pg_proc where oid = 'plm.guard_production_po_number()'::regprocedure
), reservation_contract as (
  select exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'plm.production_po_reservation'::regclass and contype = 'p'
      and pg_get_constraintdef(oid) = 'PRIMARY KEY (normalized_po)'
  ) and not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'plm.production_po_reservation'::regclass and contype = 'f'
  ) as passed
), closed_registry as (
  select bool_and(not has_table_privilege(r.role_name,t.table_name,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')) as passed
  from (values ('anon'),('authenticated'),('service_role')) r(role_name)
  cross join (values ('plm.production_po_reservation'),('plm.production_po_legacy_admission')) t(table_name)
), all_orders_reserved as (
  select not exists (
    select 1 from plm.production_order p
    where plm.normalize_production_po_number(p.production_order_number) <> '' and not exists (
      select 1 from plm.production_po_reservation r
      where r.normalized_po = plm.normalize_production_po_number(p.production_order_number)
    )
  ) as passed
)
select coalesce((select passed from trigger_contract),false)
  and coalesce((select passed from function_contract),false)
  and coalesce((select passed from reservation_contract),false)
  and coalesce((select passed from closed_registry),false)
  and coalesce((select passed from all_orders_reserved),false) as passed;
