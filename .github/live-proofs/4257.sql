-- #4257 / PopDAM #277: catalog/access proof under supabase_read_only_user.
-- Behavioral rejection and retained order rows are verified by the application
-- coordinator on the same application issue; this probe does not read private ledgers.
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
  select bool_and(not has_table_privilege(r.role_name,t.table_name,p.privilege)) as passed
  from (values ('anon'),('authenticated'),('service_role')) r(role_name)
  cross join (values ('plm.production_po_reservation'),('plm.production_po_legacy_admission')) t(table_name)
  cross join (values ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER')) p(privilege)
), normalizer_contract as (
  select provolatile = 'i' and proisstrict and proparallel = 's'
    and not prosecdef and proconfig = array['search_path=pg_catalog'] as passed
  from pg_catalog.pg_proc
  where oid = 'plm.normalize_production_po_number(text)'::regprocedure
), ledger_contract as (
  select exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261013201822') as passed
)
select coalesce((select passed from trigger_contract),false)
  and coalesce((select passed from function_contract),false)
  and coalesce((select passed from reservation_contract),false)
  and coalesce((select passed from closed_registry),false)
  and coalesce((select passed from normalizer_contract),false)
  and coalesce((select passed from ledger_contract),false) as passed;
