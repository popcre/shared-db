-- Work issue #4111; exact object claim #4112.
-- derived-from: 20260916033914
-- Restore the intended native Sheets integration using current Master Data headers.
-- Existing import snapshots and canonical item/order identities are never rewritten.
begin;

create or replace function dam.orderlist_parse_boolean(p_value text)
returns boolean language sql immutable parallel safe as $$
  select case lower(btrim(p_value))
    when 'true' then true when 'yes' then true when '1' then true when '☑️' then true
    when 'false' then false when 'no' then false when '0' then false
    else null end;
$$;

create or replace function dam.orderlist_license_status(p_row jsonb, p_discontinued boolean)
returns text language sql immutable parallel safe as $$
  select case when p_discontinued is true then 'Discontinue'
    when nullif(btrim(coalesce(p_row->>'production_approval', p_row->>'AC')), '') is not null then 'Production Approved'
    when nullif(btrim(coalesce(p_row->>'pre_production_approval', p_row->>'AB')), '') is not null then 'Pre-Pro Approved'
    when nullif(btrim(coalesce(p_row->>'pre_production_approved_comment', p_row->>'AA')), '') is not null then 'Pre Production approved w/comment'
    when nullif(btrim(coalesce(p_row->>'pre_production_resubmitted', p_row->>'Z')), '') is not null then 'Pre-Pro Resubmitted'
    when nullif(btrim(coalesce(p_row->>'pre_production_resubmit', p_row->>'Y')), '') is not null then 'Pre-Pro Resubmit'
    when nullif(btrim(coalesce(p_row->>'pre_production_sent', p_row->>'X')), '') is not null then 'Sample Submitted'
    when nullif(btrim(coalesce(p_row->>'sample_photos_received', p_row->>'W')), '') is not null then 'Sample Received'
    when nullif(btrim(coalesce(p_row->>'request_pre_production_sample', p_row->>'T')), '') is not null then 'Requested Sample'
    when nullif(btrim(coalesce(p_row->>'concept_approved_with_comments', p_row->>'S')), '') is not null then 'Concept Approved with Comments'
    when nullif(btrim(coalesce(p_row->>'concept_approval', p_row->>'R')), '') is not null then 'Concept Approved'
    when nullif(btrim(coalesce(p_row->>'concept_resubmitted', p_row->>'Q')), '') is not null then 'Concept Resubmitted'
    when nullif(btrim(coalesce(p_row->>'concept_resubmit', p_row->>'P')), '') is not null then 'Concept Resubmit'
    when nullif(btrim(coalesce(p_row->>'concept_sent', p_row->>'O')), '') is not null then 'Concept Requested'
    else 'No Info' end;
$$;

create or replace function dam.orderlist_po_status(
  p_type text, p_style text, p_assortment text, p_qty numeric, p_pack numeric,
  p_closed boolean, p_booking text, p_etd date, p_delivery date, p_sent date, p_po text
)
returns text language sql immutable parallel safe as $$
  select case
    when nullif(btrim(p_type),'') is null and nullif(btrim(p_style),'') is null and nullif(btrim(p_assortment),'') is null then null
    when nullif(btrim(p_type),'') is null or p_qty is null or p_pack is null then 'Not Enough Line Info'
    when p_closed is true then 'Close tracking'
    when p_type = 'FOB' and p_booking = 'Booked' then 'Booked FOB'
    when p_type <> 'FOB' and p_etd is not null then 'Confirmed Booking'
    when p_type <> 'FOB' and p_booking = 'Booked' then 'Requesting Booking'
    when p_delivery is not null then 'Confirmed CRD'
    when p_sent is not null then 'Sent PO'
    when nullif(btrim(p_po),'') is null then 'PO Not Create'
    else 'Creating PO' end;
$$;

create or replace function dam.orderlist_cargo_forecast(p_type text, p_ship_to text, p_start date)
returns date language sql immutable parallel safe as $$
  select case when nullif(btrim(p_type),'') is null or p_start is null then null
    when p_type = 'FOB' then p_start - 7
    when p_type = 'C Stock' and upper(btrim(p_ship_to)) = 'NJ' then p_start - 37
    when upper(btrim(p_ship_to)) in ('NY','NJ') then p_start - 44
    when upper(btrim(p_ship_to)) in ('LA','CA') then p_start - 23
    when upper(btrim(p_ship_to)) = 'NC' then p_start - 46
    else null end;
$$;

-- The bridge may contain several tracker rows for one item. Never choose one by
-- row order. Only an unambiguous set of equal operational facts is publishable.
create or replace function dam.orderlist_product_facts(p_item_id uuid, p_catalog text)
returns jsonb language sql stable security invoker set search_path = pg_catalog, pg_temp as $$
  with candidates as (
    select b.id as bridge_id, s.id as tracker_id, s.tracker_type,
      jsonb_build_object(
        'license_status', case when s.tracker_type = 'generic' then 'Generic Item'
          else dam.orderlist_license_status(s.row_data, s.discontinued) end,
        'licensor', s.licensor, 'customer', s.customer,
        'default_vendor', s.default_vendor,
        'sample_vendor', coalesce(s.row_data->>'sample_vendor', s.row_data->>case when s.tracker_type='licensed' then 'U' else 'S' end),
        'test_report', dam.orderlist_parse_boolean(coalesce(s.row_data->>'test_report', s.row_data->>case when s.tracker_type='licensed' then 'AI' else 'AE' end)),
        'professional_photos', dam.orderlist_parse_boolean(coalesce(s.row_data->>'professional_photos', s.row_data->>case when s.tracker_type='licensed' then 'AH' else 'AD' end)),
        'contractual_sample_reorder', case when s.tracker_type='licensed' then dam.orderlist_parse_boolean(coalesce(s.row_data->>'contractual_samples_reorder',s.row_data->>'AO')) else null end
      ) as facts
    from plm.style_tracker_item_bridge b
    join public.style_tracker_rows s on s.id=b.style_tracker_row_id
    where b.plm_item_id=p_item_id and (p_catalog is null or s.tracker_type=p_catalog)
  ), summary as (
    select count(*) as row_count, count(distinct facts) as distinct_facts,
      (array_agg(facts))[1] as facts,
      case when count(*)=1 then (array_agg(bridge_id))[1] end as bridge_id,
      case when count(*)=1 then (array_agg(tracker_id))[1] end as tracker_id,
      case when count(distinct tracker_type)=1 then min(tracker_type) end as tracker_type
    from candidates
  ) select case when distinct_facts=1 then facts else '{}'::jsonb end || jsonb_build_object(
      'source', case when row_count=0 then 'unavailable' when distinct_facts>1 then 'ambiguous' else 'master_data' end,
      'bridge_id', bridge_id, 'tracker_id', tracker_id, 'tracker_type', tracker_type
    ) from summary;
$$;

create table if not exists dam.orderlist_sample_depth (
  sku_normalized text not null,
  customer_normalized text not null,
  depth_inches numeric check (depth_inches > 0),
  depth_raw text,
  source_workbook_id text,
  source_row_number integer check (source_row_number > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid,
  primary key (sku_normalized, customer_normalized),
  check (sku_normalized=lower(btrim(sku_normalized)) and sku_normalized<>''),
  check (customer_normalized=lower(btrim(customer_normalized)) and customer_normalized<>'')
);
alter table dam.orderlist_sample_depth enable row level security;
create policy orderlist_sample_depth_read on dam.orderlist_sample_depth for select to authenticated using (true);
create policy orderlist_sample_depth_write on dam.orderlist_sample_depth for all to authenticated
  using (app.has_role('administrator'::app.app_role)) with check (app.has_role('administrator'::app.app_role));
grant select on dam.orderlist_sample_depth to authenticated;
grant all on dam.orderlist_sample_depth to service_role;

create table if not exists dam.orderlist_customer_settings (
  customer_normalized text primary key,
  suffix text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  check (customer_normalized=lower(btrim(customer_normalized)) and customer_normalized<>''),
  check (length(suffix) between 1 and 50)
);
alter table dam.orderlist_customer_settings enable row level security;
create policy orderlist_customer_settings_read on dam.orderlist_customer_settings for select to authenticated using (true);
create policy orderlist_customer_settings_write on dam.orderlist_customer_settings for all to authenticated
  using (app.has_role('administrator'::app.app_role)) with check (app.has_role('administrator'::app.app_role));
grant select on dam.orderlist_customer_settings to authenticated;
grant all on dam.orderlist_customer_settings to service_role;

-- PO-level facts have one owner and are inherited by lines; they are not per-SKU events.
create table if not exists dam.order_tracking_ext (
  order_id uuid primary key references plm.production_order(id) on delete cascade,
  agent text, cbm numeric check (cbm >= 0), comment text, vessel text,
  sent_to_coldlion boolean, worksheet_done boolean, inspection_passed boolean,
  document_invoice boolean, document_packing_list boolean, document_bill_of_lading boolean,
  document_tsca boolean, document_lacey_act boolean, document_telex boolean,
  request_wire boolean, payment_note text,
  updated_at timestamptz not null default now(), updated_by uuid
);
alter table dam.order_tracking_ext enable row level security;
create policy order_tracking_ext_read on dam.order_tracking_ext for select to authenticated using (true);
create policy order_tracking_ext_write on dam.order_tracking_ext for all to authenticated
  using (app.has_role('administrator'::app.app_role)) with check (app.has_role('administrator'::app.app_role));
grant select on dam.order_tracking_ext to authenticated;
grant all on dam.order_tracking_ext to service_role;

create or replace view api.dam_order_sample_depth with (security_invoker=true) as
  select * from dam.orderlist_sample_depth;
create or replace view api.dam_order_customer_settings with (security_invoker=true) as
  select * from dam.orderlist_customer_settings;
grant select on api.dam_order_sample_depth, api.dam_order_customer_settings to authenticated, service_role;
revoke all on api.dam_order_sample_depth, api.dam_order_customer_settings from anon;

create or replace function public.upsert_dam_order_sample_depth(p_sku text, p_customer text, p_depth_inches numeric)
returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
  if auth.uid() is null or app.has_role('administrator'::app.app_role) is not true then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  insert into dam.orderlist_sample_depth(sku_normalized,customer_normalized,depth_inches,updated_by)
  values(lower(btrim(p_sku)),lower(btrim(p_customer)),p_depth_inches,auth.uid())
  on conflict(sku_normalized,customer_normalized) do update set depth_inches=excluded.depth_inches, updated_at=now(),updated_by=auth.uid();
end;
$$;
create or replace function public.upsert_dam_order_customer_settings(p_customer text, p_suffix text)
returns void language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
begin
  if auth.uid() is null or app.has_role('administrator'::app.app_role) is not true then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  insert into dam.orderlist_customer_settings(customer_normalized,suffix,updated_by)
  values(lower(btrim(p_customer)),btrim(p_suffix),auth.uid())
  on conflict(customer_normalized) do update set suffix=excluded.suffix,updated_at=now(),updated_by=auth.uid();
end;
$$;

create or replace function public.update_dam_order_tracking(p_order_id uuid,p_patch jsonb)
returns uuid language plpgsql security definer set search_path=pg_catalog,pg_temp as $$
declare
  v_key text;
  v_type text;
  v_header_keys text[] := array['sent_po_date','vendor_delivery_date','booking_state','etd','eta','container_booking_group','mbl','close_tracking'];
  v_extra_keys text[] := array['agent','cbm','comment','vessel','sent_to_coldlion','worksheet_done','inspection_passed','document_invoice','document_packing_list','document_bill_of_lading','document_tsca','document_lacey_act','document_telex','request_wire','payment_note'];
begin
  if auth.uid() is null or app.has_role('administrator'::app.app_role) is not true then
    raise exception 'Administrator access required' using errcode='42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch)<>'object' then
    raise exception 'Tracking patch must be an object' using errcode='22023';
  end if;
  for v_key in select jsonb_object_keys(p_patch) loop
    if not v_key=any(v_header_keys||v_extra_keys) then
      raise exception 'Tracking field % is not editable',v_key using errcode='42501';
    end if;
  end loop;
  perform 1 from plm.production_order where id=p_order_id for update;
  if not found then raise exception 'Order not found' using errcode='P0002'; end if;
  insert into dam.order_tracking_ext(order_id,updated_by) values(p_order_id,auth.uid())
    on conflict(order_id) do nothing;
  -- Identifier formatting is safe only after the closed allowlist check above.
  -- Values are parameters. Absent keys leave existing facts untouched.
  for v_key in select jsonb_object_keys(p_patch) loop
    v_type := case when v_key=any(array['sent_po_date','vendor_delivery_date','etd','eta']) then 'date'
      when v_key='cbm' then 'numeric'
      when v_key=any(array['close_tracking','sent_to_coldlion','worksheet_done','inspection_passed','document_invoice','document_packing_list','document_bill_of_lading','document_tsca','document_lacey_act','document_telex','request_wire']) then 'boolean'
      else 'text' end;
    if v_key=any(v_header_keys) then
      execute format('update plm.production_order set %I=$1::%s,updated_at=now() where id=$2',v_key,v_type)
        using p_patch->>v_key,p_order_id;
    else
      execute format('update dam.order_tracking_ext set %I=$1::%s,updated_at=now(),updated_by=auth.uid() where order_id=$2',v_key,v_type)
        using p_patch->>v_key,p_order_id;
    end if;
  end loop;
  return p_order_id;
end;
$$;

-- Existing column order/types are retained; new operational outputs append.
create or replace view api.dam_order_list with (security_invoker=true) as
SELECT pol.id AS order_line_id,
    po.id AS order_id,
    po.production_order_number,
    case when po.source_system='coldlion' and po.production_order_number like 'coldlion/%' then po.status else dam.orderlist_po_status(pol.order_type,pol.sku,pol.assortment_id,pol.quantity_ordered,pol.case_pack,po.close_tracking,po.booking_state,po.etd,coalesce(po.vendor_delivery_date,po.seal_container_date),po.sent_po_date,po.production_order_number) end AS order_status,
    po.company_id,
    cust.customer_name,
    po.factory_id,
    fact.vendor_name,
    po.metadata ->> 'ordering_company'::text AS ordering_company,
    po.order_date,
    po.sent_po_date,
    coalesce(po.vendor_delivery_date,po.seal_container_date) AS seal_container_date,
    po.vendor_delivery_date,
    po.requested_ship_date,
    po.actual_ship_date,
    po.booking_state,
    po.etd,
    po.eta,
    coalesce(po.warehouse_date,po.eta+5) AS warehouse_date,
    po.container_booking_group,
    po.mbl,
    po.close_tracking,
    po.voided_at AS order_voided_at,
    po.void_reason AS order_void_reason,
    pol.line_number,
    pol.order_person,
    pol.order_type,
    case when pol.order_type='David Sample' then 'David' when pol.order_type='Contractual Sample' then 'CONT' else coalesce(customer_settings.suffix,pol.customer_suffix) end AS customer_suffix,
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
    case when pol.case_pack>0 and pol.quantity_ordered is not null and pol.quantity_ordered>=pol.case_pack then pol.quantity_ordered/pol.case_pack end AS cases_reported,
    pol.ship_to,
    pol.start_ship_date,
    pol.start_ship_raw,
    pol.cancel_date,
    pol.cancel_raw,
    dam.orderlist_cargo_forecast(pol.order_type,pol.ship_to,pol.start_ship_date) AS cargo_forecast_date,
    case when nullif(btrim(pol.order_type),'') is null then null when pol.start_ship_date is null then 'NoDate' when dam.orderlist_cargo_forecast(pol.order_type,pol.ship_to,pol.start_ship_date) is null then 'N/A' end AS cargo_forecast_raw,
    case when product.facts->>'source'='master_data' then product.facts->>'test_report' when pol.item_id is null then pol.test_report end AS test_report,
    case when product.facts->>'source'='master_data' then product.facts->>'professional_photos' when pol.item_id is null then pol.professional_photos end AS professional_photos,
    case when product.facts->>'source'='master_data' then (product.facts->>'contractual_sample_reorder')::boolean when pol.item_id is null then pol.contractual_sample_reorder end AS contractual_sample_reorder,
    pol.status AS line_status,
    pol.voided_at AS line_voided_at,
    pol.void_reason AS line_void_reason,
    pol.source_style_type,
    pol.master_data_match_status,
    pol.item_id,
    item.item_number,
    item.style_number AS item_style_number,
    item.name AS item_name,
    item.description AS item_description,
    (product.facts->>'bridge_id')::uuid AS style_tracker_bridge_id,
    (product.facts->>'tracker_id')::uuid AS style_tracker_row_id,
    product.facts->>'tracker_type' AS master_data_tracker_type,
    item.description AS master_data_description,
    product.facts->>'license_status' AS master_data_license_status,
    product.facts->>'licensor' AS master_data_licensor,
    product.facts->>'default_vendor' AS master_data_default_vendor,
    product.facts->>'customer' AS master_data_customer,
    pol.metadata #>> '{order_list_snapshot,sku}'::text[] AS snapshot_sku,
    pol.metadata #>> '{order_list_snapshot,description}'::text[] AS snapshot_description,
    pol.metadata #>> '{order_list_snapshot,license_status}'::text[] AS snapshot_license_status,
    pol.metadata #>> '{order_list_snapshot,style_type}'::text[] AS snapshot_style_type,
    pol.metadata #>> '{order_list_snapshot,source_row}'::text[] AS snapshot_source_row,
    pol.item_id IS NULL AS item_link_missing,
    pol.item_id IS NOT NULL AND pol.source_style_type IS NOT NULL
      AND NOT EXISTS(select 1 from plm.style_tracker_item_bridge b where b.plm_item_id=pol.item_id and b.tracker_type=pol.source_style_type)
      AND EXISTS(select 1 from plm.style_tracker_item_bridge b where b.plm_item_id=pol.item_id) AS item_link_type_mismatch,
    google_ref.source_id AS google_source_id,
    coldlion_ref.source_id AS coldlion_source_id,
    pol.created_at AS line_created_at,
    pol.updated_at AS line_updated_at,
    case when pol.item_id is null then 'at_import' else product.facts->>'source' end AS product_workflow_source,
    product.facts->>'sample_vendor' AS master_data_sample_vendor,
    sample.depth_inches AS sample_depth_inches,
    case when pol.case_pack=0 then 'Wrong Input' when pol.case_pack<0 then 'Wrong Input' when pol.quantity_ordered is not null and pol.case_pack>pol.quantity_ordered then 'Wrong QTY' end AS cases_error
   FROM plm.production_order_line pol
     JOIN plm.production_order po ON po.id = pol.production_order_id
     LEFT JOIN dam.dam_order_list_customer_directory cust ON cust.customer_id = po.company_id
     LEFT JOIN dam.dam_order_list_vendor_directory fact ON fact.vendor_id = po.factory_id
     LEFT JOIN plm.item item ON item.id = pol.item_id
     LEFT JOIN LATERAL (select dam.orderlist_product_facts(pol.item_id,pol.source_style_type) AS facts) product ON true
     LEFT JOIN dam.orderlist_sample_depth sample ON sample.sku_normalized=pol.sku_normalized AND sample.customer_normalized=lower(btrim(cust.customer_name))
     LEFT JOIN dam.orderlist_customer_settings customer_settings ON customer_settings.customer_normalized=lower(btrim(cust.customer_name))
     LEFT JOIN plm.production_order_line_source_ref google_ref ON google_ref.production_order_line_id = pol.id AND google_ref.source_system = 'google_order_list'::text
     LEFT JOIN plm.production_order_line_source_ref coldlion_ref ON coldlion_ref.production_order_line_id = pol.id AND coldlion_ref.source_system = 'coldlion'::text;

-- Aggregate canonical lines, not the imported assortment parent snapshot. Each
-- physical component is counted once. ColdLion sales-history placeholders are
-- not Google production POs and must not be presented as purchase commitments.
create or replace view api.dam_order_tracking with (security_invoker=true) as
with lines as (
  select order_id,count(*) as line_count,
    sum(cases_reported) filter(where order_type is distinct from 'Contractual Sample' and order_type is distinct from 'David Sample') as total_cases,
    count(*) filter(where cases_error is not null) as invalid_case_lines,
    count(*) filter(where dam.orderlist_parse_boolean(test_report) is not true) as missing_test_reports,
    count(*) filter(where dam.orderlist_parse_boolean(professional_photos) is not true) as missing_photos,
    count(*) filter(where product_workflow_source is distinct from 'master_data') as unresolved_product_lines,
    case when count(distinct order_type) filter(where order_type not in('Contractual Sample','David Sample'))=1
      then min(order_type) filter(where order_type not in('Contractual Sample','David Sample')) end as order_type,
    min(start_ship_date) as start_ship_date,min(cancel_date) as cancel_date,min(cargo_forecast_date) as cargo_forecast_date,
    string_agg(distinct customer_po_number,E'\n' order by customer_po_number) as customer_po_number,
    string_agg(distinct customer_suffix,E'\n' order by customer_suffix) as customer_suffix,
    jsonb_agg(jsonb_build_object('line_id',order_line_id,'sku',sku,'assortment',assortment_id,'quantity',quantity_ordered,
      'description',item_description,'license_status',master_data_license_status,'test_report',test_report,
      'professional_photos',professional_photos,'default_vendor',master_data_default_vendor,'sample_vendor',master_data_sample_vendor)
      order by assortment_id nulls last,assortment_component_ordinal nulls last,line_number,order_line_id) as components
  from api.dam_order_list
  where order_voided_at is null and line_voided_at is null
  group by order_id
)
select po.id as order_id,po.production_order_number,po.order_date,po.voided_at as order_voided_at,
  cust.customer_name,fact.vendor_name,po.factory_id,po.company_id,
  lines.line_count,lines.total_cases,lines.invalid_case_lines,lines.missing_test_reports,lines.missing_photos,
  lines.unresolved_product_lines,lines.order_type,lines.start_ship_date,lines.cancel_date,lines.cargo_forecast_date,
  lines.customer_po_number,lines.customer_suffix,lines.components,
  po.sent_po_date,coalesce(po.vendor_delivery_date,po.seal_container_date) as vendor_delivery_date,
  case when po.vendor_delivery_date is not null then po.vendor_delivery_date +
    case lines.order_type when 'FOB' then 5 when 'POE' then 21 when 'C Stock' then 27 end end as seal_container_forecast,
  po.booking_state,po.etd,po.eta,coalesce(po.warehouse_date,po.eta+5) as warehouse_date,
  case when lines.order_type='FOB' then null
    when lines.order_type='POE' then po.eta-lines.cancel_date
    else coalesce(po.warehouse_date,po.eta+5)-lines.cancel_date end as days_delay,
  case when lines.order_type='POE' and cust.customer_name='Burlington' and ext.worksheet_done is not true
    then po.eta-current_date-5 end as worksheet_days_remaining,
  po.container_booking_group,po.mbl,po.close_tracking,
  ext.agent,ext.cbm,ext.comment,ext.vessel,ext.sent_to_coldlion,ext.worksheet_done,ext.inspection_passed,
  ext.document_invoice,ext.document_packing_list,ext.document_bill_of_lading,ext.document_tsca,ext.document_lacey_act,
  ext.document_telex,ext.request_wire,ext.payment_note,ext.updated_at as tracking_updated_at
from plm.production_order po
left join lines on lines.order_id=po.id
left join dam.dam_order_list_customer_directory cust on cust.customer_id=po.company_id
left join dam.dam_order_list_vendor_directory fact on fact.vendor_id=po.factory_id
left join dam.order_tracking_ext ext on ext.order_id=po.id
where not (coalesce(po.source_system='coldlion',false) and coalesce(po.production_order_number like 'coldlion/%',false));

-- The native sheet's verified activity window is 14 months. Counts are PO
-- counts; sales-history quantities or stage rows are never summed as purchases.
create or replace view api.dam_order_vendor_statistics with (security_invoker=true) as
select factory_id,vendor_name,count(*) as order_count,
  count(*) filter(where close_tracking is true) as closed_orders,
  count(*) filter(where close_tracking is not true and order_voided_at is null) as open_orders,
  max(sent_po_date) filter(where order_voided_at is null and production_order_number not ilike '%cancel%') as last_sent_po_date,
  case when max(sent_po_date) filter(where order_voided_at is null and production_order_number not ilike '%cancel%') > (current_date-interval '14 months')::date
    then 'Active' else 'Inactive' end as activity_status
from api.dam_order_tracking
where vendor_name is not null
group by factory_id,vendor_name;

grant select on api.dam_order_list,api.dam_order_tracking,api.dam_order_vendor_statistics to authenticated,service_role;
revoke all on api.dam_order_tracking,api.dam_order_vendor_statistics from anon;

revoke all on function dam.orderlist_parse_boolean(text) from public,anon;
revoke all on function dam.orderlist_license_status(jsonb,boolean) from public,anon;
revoke all on function dam.orderlist_po_status(text,text,text,numeric,numeric,boolean,text,date,date,date,text) from public,anon;
revoke all on function dam.orderlist_cargo_forecast(text,text,date) from public,anon;
revoke all on function dam.orderlist_product_facts(uuid,text) from public,anon;
grant execute on function dam.orderlist_parse_boolean(text),dam.orderlist_license_status(jsonb,boolean),
  dam.orderlist_po_status(text,text,text,numeric,numeric,boolean,text,date,date,date,text),
  dam.orderlist_cargo_forecast(text,text,date),dam.orderlist_product_facts(uuid,text) to authenticated,service_role;
revoke all on function public.update_dam_order_tracking(uuid,jsonb),
  public.upsert_dam_order_sample_depth(text,text,numeric),public.upsert_dam_order_customer_settings(text,text) from public,anon;
grant execute on function public.update_dam_order_tracking(uuid,jsonb),
  public.upsert_dam_order_sample_depth(text,text,numeric),public.upsert_dam_order_customer_settings(text,text) to authenticated;

do $verify$
begin
  if to_regclass('api.dam_order_tracking') is null or to_regclass('api.dam_order_vendor_statistics') is null
    or to_regclass('dam.orderlist_sample_depth') is null or to_regprocedure('public.update_dam_order_tracking(uuid,jsonb)') is null then
    raise exception 'OrderList integration contract is incomplete';
  end if;
  if has_function_privilege('anon','public.update_dam_order_tracking(uuid,jsonb)','execute')
    or has_table_privilege('anon','api.dam_order_tracking','select') then
    raise exception 'OrderList integration must not be anonymously accessible';
  end if;
end;
$verify$;

-- The Master Data page uses the same status calculator as OrderList. A bounded
-- RPC avoids re-deriving the existing view and its unrelated ERP/RFQ joins.
create or replace function public.get_dam_style_tracker_license_status(p_row_ids uuid[])
returns table(id uuid,license_status text)
language plpgsql stable security invoker set search_path=pg_catalog,pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if cardinality(p_row_ids)>1000 then raise exception 'At most 1000 rows per request' using errcode='22023'; end if;
  return query select r.id,case when r.tracker_type='licensed'
    then dam.orderlist_license_status(r.row_data,r.discontinued) else r.license_status end
    from public.style_tracker_rows r where r.id=any(p_row_ids);
end;
$$;
revoke all on function public.get_dam_style_tracker_license_status(uuid[]) from public,anon;
grant execute on function public.get_dam_style_tracker_license_status(uuid[]) to authenticated;

notify pgrst,'reload schema';
commit;
