-- Issue #4964: rudimentary per-retailer selling signal (red/yellow/green) on
-- items. One row per (item, retailer); a retailer is a core.customer row (the
-- CRM/PM retailer master). The signal is an owner-entered judgment, never
-- computed from orders.
-- derived-from: none

begin;

create table plm.item_retailer_selling (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references plm.item(id) on delete restrict,
  retailer_id uuid not null references core.customer(id) on delete restrict,
  selling_signal text not null
    constraint item_retailer_selling_signal_check
    check (selling_signal in ('red', 'yellow', 'green')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint item_retailer_selling_item_retailer_key unique (item_id, retailer_id)
);

create index item_retailer_selling_retailer_id_idx
  on plm.item_retailer_selling (retailer_id);

comment on table plm.item_retailer_selling is
  'Rudimentary selling signal per item per retailer (issue #4964). A retailer is a core.customer row. selling_signal is an owner-entered traffic light (red/yellow/green), never computed from orders.';

comment on column plm.item_retailer_selling.selling_signal is
  'Traffic-light selling judgment: red (poor), yellow (middling), or green (strong).';

comment on column plm.item_retailer_selling.retailer_id is
  'The retailer this signal is for; a core.customer row.';

-- Deny-by-default until consuming apps explicitly grant their roles,
-- matching the other item-master tables.
alter table plm.item_retailer_selling enable row level security;
revoke all on table plm.item_retailer_selling from public, anon, authenticated, service_role;

-- Catalogue-only verification of the claimed shape and deny-by-default access.
do $verify$
declare
  actual_columns integer;
begin
  select count(*) into actual_columns
    from pg_catalog.pg_attribute
   where attrelid = pg_catalog.to_regclass('plm.item_retailer_selling')
     and attnum > 0 and not attisdropped;

  if actual_columns <> 6 then
    raise exception 'plm.item_retailer_selling: expected 6 columns, found %', actual_columns;
  end if;

  if not exists (
    select 1 from pg_catalog.pg_class
     where oid = pg_catalog.to_regclass('plm.item_retailer_selling')
       and relkind = 'r' and relrowsecurity
  ) then
    raise exception 'plm.item_retailer_selling: ordinary table with RLS required';
  end if;

  if exists (
    select 1 from pg_catalog.pg_policies
     where schemaname = 'plm' and tablename = 'item_retailer_selling'
  ) then
    raise exception 'plm.item_retailer_selling: unexpected RLS policy';
  end if;
end
$verify$;

commit;
