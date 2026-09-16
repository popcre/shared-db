-- Issue #2988; claim #3005. PopDAM OrderList must open for every signed-in
-- PopDAM user, including one with no app.user_role row.
-- derived-from: 20260810010000
--
-- PRODUCTION DIAGNOSIS (read-only, 2026-09-15/16, qsllyeztdwjgirsysgai).
--   api.dam_order_list is a security-invoker view that LEFT JOINs core.customer
--   (826 rows) and core.factory (93 rows). Both carry the `shared_read` policy
--   `app.has_any_role(array[administrator,sales,licensing,designer,viewer,vendor])`.
--   That qual takes no row-dependent argument but is STABLE, so PostgreSQL
--   evaluates it once PER ROW instead of folding it. Measured under
--   yzhou@popcre.com's own JWT claims on production, 826 evaluations of that
--   exact qual cost 5,373 ms and every one returned false. That is the whole of
--   the ~3.44 s customer node and ~0.41 s factory node in the issue's plan, and
--   the reason a bounded 500-row page reaches the 8 s authenticated timeout.
--   Reading the same two columns with no policy evaluation costs 1.2 ms.
--
-- WHAT THIS CHANGES, AND WHAT IT DELIBERATELY DOES NOT.
--   The two joins now read a pair of NARROW security-definer directories that
--   return only (id, name) -- the exact two values the grid already displays --
--   for authenticated callers. Each is executed ONCE per query, not once per
--   row, because PostgreSQL does not inline a SECURITY DEFINER set-returning
--   function. Nothing else about the view changes: same columns, same order,
--   same types, same rows, same joins, same ordering, same LIMIT behaviour.
--
--   * api.dam_order_list STAYS security_invoker = true. Issue #2662 (definer
--     views and cross-application leakage) is untouched and this migration does
--     not pre-empt it: every other input of the view is still read under the
--     caller's own RLS.
--   * core.customer and core.factory policies, grants and columns are NOT
--     changed. Direct access to either table is exactly what it was, for every
--     role. A user with no business role still cannot select those tables, and
--     still cannot see any column beyond a party's display name through this
--     view -- which is already what the grid shows and what a role-bearing user
--     has always seen there.
--   * The helpers live in `app`, which PostgREST does not expose, so they are
--     not reachable as RPC. anon and PUBLIC get no EXECUTE, and each helper
--     refuses a non-authenticated caller outright.
--   * No timeout is raised, no dataset is loaded in full, and no index,
--     materialized view or scheduled job is introduced.

create or replace function app.dam_order_list_customer_directory()
returns table (customer_id uuid, customer_name text)
language plpgsql
stable
security definer
set search_path = pg_catalog, auth
rows 1000
as $function$
begin
  if auth.uid() is null or auth.role() is distinct from 'authenticated' then
    raise insufficient_privilege using message = 'Authenticated access required';
  end if;
  return query select c.id, c.name from core.customer c;
end;
$function$;

create or replace function app.dam_order_list_vendor_directory()
returns table (vendor_id uuid, vendor_name text)
language plpgsql
stable
security definer
set search_path = pg_catalog, auth
rows 1000
as $function$
begin
  if auth.uid() is null or auth.role() is distinct from 'authenticated' then
    raise insufficient_privilege using message = 'Authenticated access required';
  end if;
  return query select f.id, f.name from core.factory f;
end;
$function$;

revoke all on function app.dam_order_list_customer_directory() from public, anon;
revoke all on function app.dam_order_list_vendor_directory() from public, anon;
-- service_role keeps EXECUTE because it already holds SELECT on the view and
-- would otherwise lose the two name columns it can read today.
grant execute on function app.dam_order_list_customer_directory() to authenticated, service_role;
grant execute on function app.dam_order_list_vendor_directory() to authenticated, service_role;

comment on function app.dam_order_list_customer_directory() is
  'Issue #2988. Authenticated-only (id, name) customer directory for api.dam_order_list. Returns no other column and is evaluated once per OrderList query; core.customer policies are unchanged.';
comment on function app.dam_order_list_vendor_directory() is
  'Issue #2988. Authenticated-only (id, name) vendor directory for api.dam_order_list. Returns no other column and is evaluated once per OrderList query; core.factory policies are unchanged.';

create or replace view api.dam_order_list as
select
  -- identity
  pol.id                                    as order_line_id,
  po.id                                     as order_id,

  -- order (header) facts
  po.production_order_number,
  po.status                                 as order_status,
  po.company_id,
  cust.customer_name                        as customer_name,
  po.factory_id,
  fact.vendor_name                          as vendor_name,
  po.metadata ->> 'ordering_company'        as ordering_company,
  po.order_date,
  po.sent_po_date,
  po.seal_container_date,
  po.vendor_delivery_date,
  po.requested_ship_date,
  po.actual_ship_date,
  po.booking_state,
  po.etd,
  po.eta,
  po.warehouse_date,
  po.container_booking_group,
  po.mbl,
  po.close_tracking,
  po.voided_at                              as order_voided_at,
  po.void_reason                            as order_void_reason,

  -- line facts
  pol.line_number,
  pol.order_person,
  pol.order_type,
  pol.customer_suffix,
  pol.customer_po_number,
  pol.assortment_id,
  pol.assortment_component_ordinal,
  pol.sku,
  pol.sku_normalized,
  pol.quantity_ordered,
  pol.quantity_shipped,
  pol.unit_cost,
  pol.order_depth_inches,
  pol.case_pack,
  pol.cases_reported,
  pol.ship_to,
  pol.start_ship_date,
  pol.start_ship_raw,
  pol.cancel_date,
  pol.cancel_raw,
  pol.cargo_forecast_date,
  pol.cargo_forecast_raw,
  pol.test_report,
  pol.professional_photos,
  pol.contractual_sample_reorder,
  pol.status                                as line_status,
  pol.voided_at                             as line_voided_at,
  pol.void_reason                           as line_void_reason,

  -- how this line resolved to a product
  pol.source_style_type,
  pol.master_data_match_status,
  pol.item_id,

  -- CURRENT product facts (live, read-only in the UI)
  item.item_number                          as item_number,
  item.style_number                         as item_style_number,
  item.name                                 as item_name,
  item.description                          as item_description,
  bridge.id                                 as style_tracker_bridge_id,
  bridge.style_tracker_row_id,
  bridge.tracker_type                       as master_data_tracker_type,
  str.description                           as master_data_description,
  str.license_status                        as master_data_license_status,
  str.licensor                              as master_data_licensor,
  str.default_vendor                        as master_data_default_vendor,
  str.customer                              as master_data_customer,

  -- IMMUTABLE source snapshot (display fallback only, never current truth)
  pol.metadata #>> '{order_list_snapshot,sku}'            as snapshot_sku,
  pol.metadata #>> '{order_list_snapshot,description}'    as snapshot_description,
  pol.metadata #>> '{order_list_snapshot,license_status}' as snapshot_license_status,
  pol.metadata #>> '{order_list_snapshot,style_type}'     as snapshot_style_type,
  pol.metadata #>> '{order_list_snapshot,source_row}'     as snapshot_source_row,

  -- diagnostics the grid renders as a badge, computed here so every client agrees
  (pol.item_id is null)                     as item_link_missing,
  (
    pol.item_id is not null
    and bridge.id is not null
    and pol.source_style_type is not null
    and bridge.tracker_type is distinct from pol.source_style_type
  )                                         as item_link_type_mismatch,

  -- provenance
  google_ref.source_id                      as google_source_id,
  coldlion_ref.source_id                    as coldlion_source_id,
  pol.created_at                            as line_created_at,
  pol.updated_at                            as line_updated_at
from plm.production_order_line pol
join plm.production_order po
  on po.id = pol.production_order_id
-- Issue #2988: the two party names come from narrow authenticated-only
-- directories, evaluated once per query, instead of a per-row RLS policy
-- evaluation over core.customer / core.factory.
left join app.dam_order_list_customer_directory() cust
  on cust.customer_id = po.company_id
left join app.dam_order_list_vendor_directory() fact
  on fact.vendor_id = po.factory_id
left join plm.item item
  on item.id = pol.item_id
left join plm.style_tracker_item_bridge bridge
  on bridge.plm_item_id = pol.item_id
left join public.style_tracker_rows str
  on str.id = bridge.style_tracker_row_id
left join plm.production_order_line_source_ref google_ref
  on google_ref.production_order_line_id = pol.id
 and google_ref.source_system = 'google_order_list'
left join plm.production_order_line_source_ref coldlion_ref
  on coldlion_ref.production_order_line_id = pol.id
 and coldlion_ref.source_system = 'coldlion';

-- Re-asserted, not changed: the view keeps the invoker semantics fixed by
-- 20260810110000 and the same grants it already carries. anon stays excluded.
alter view api.dam_order_list set (security_invoker = true);
revoke all on api.dam_order_list from public, anon;
grant select on api.dam_order_list to authenticated;
grant select, insert, update, delete on api.dam_order_list to service_role;

comment on view api.dam_order_list is
  'PopDAM OrderList read contract. security_invoker view over plm order/line/item/bridge inputs under the caller''s own RLS. Issue #2988: customer and vendor display names come from app.dam_order_list_customer_directory() and app.dam_order_list_vendor_directory(), narrow authenticated-only (id, name) directories evaluated once per query, so a signed-in user with no business role loads the bounded page without the per-row core.customer and core.factory policy cost. Direct core.customer and core.factory access is unchanged.';
