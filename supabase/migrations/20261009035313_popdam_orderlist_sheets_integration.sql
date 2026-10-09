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

create or replace function dam.orderlist_parse_number(p_value text)
returns numeric language plpgsql immutable parallel safe set search_path=pg_catalog,pg_temp as $$
declare v numeric;
begin
  if nullif(btrim(p_value),'') is null then return null; end if;
  v:=p_value::numeric;
  if v::text in ('NaN','Infinity','-Infinity') then return null; end if;
  return v;
exception when invalid_text_representation or numeric_value_out_of_range then return null;
end;
$$;

create or replace function dam.orderlist_license_status(p_row jsonb, p_discontinued boolean)
returns text language sql immutable parallel safe as $$
  select case when p_discontinued is true then 'Discontinue'
    when nullif(btrim(case when p_row ? 'production_approval' then p_row->>'production_approval' else p_row->>'AC' end), '') is not null then 'Production Approved'
    when nullif(btrim(case when p_row ? 'pre_production_approval' then p_row->>'pre_production_approval' else p_row->>'AB' end), '') is not null then 'Pre-Pro Approved'
    when nullif(btrim(case when p_row ? 'pre_production_approved_comment' then p_row->>'pre_production_approved_comment' else p_row->>'AA' end), '') is not null then 'Pre Production approved w/comment'
    when nullif(btrim(case when p_row ? 'pre_production_resubmitted' then p_row->>'pre_production_resubmitted' else p_row->>'Z' end), '') is not null then 'Pre-Pro Resubmitted'
    when nullif(btrim(case when p_row ? 'pre_production_resubmit' then p_row->>'pre_production_resubmit' else p_row->>'Y' end), '') is not null then 'Pre-Pro Resubmit'
    when nullif(btrim(case when p_row ? 'pre_production_sent' then p_row->>'pre_production_sent' else p_row->>'X' end), '') is not null then 'Sample Submitted'
    when nullif(btrim(case when p_row ? 'sample_photos_received' then p_row->>'sample_photos_received' else p_row->>'W' end), '') is not null then 'Sample Received'
    when nullif(btrim(case when p_row ? 'request_pre_production_sample' then p_row->>'request_pre_production_sample' else p_row->>'T' end), '') is not null then 'Requested Sample'
    when nullif(btrim(case when p_row ? 'concept_approved_with_comments' then p_row->>'concept_approved_with_comments' else p_row->>'S' end), '') is not null then 'Concept Approved with Comments'
    when nullif(btrim(case when p_row ? 'concept_approval' then p_row->>'concept_approval' else p_row->>'R' end), '') is not null then 'Concept Approved'
    when nullif(btrim(case when p_row ? 'concept_resubmitted' then p_row->>'concept_resubmitted' else p_row->>'Q' end), '') is not null then 'Concept Resubmitted'
    when nullif(btrim(case when p_row ? 'concept_resubmit' then p_row->>'concept_resubmit' else p_row->>'P' end), '') is not null then 'Concept Resubmit'
    when nullif(btrim(case when p_row ? 'concept_sent' then p_row->>'concept_sent' else p_row->>'O' end), '') is not null then 'Concept Requested'
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
          when s.tracker_type='licensed' then dam.orderlist_license_status(s.row_data, s.discontinued) else s.license_status end,
        'licensor', s.licensor, 'customer', s.customer,
        'default_vendor', s.default_vendor,
        'sample_vendor', case when s.row_data ? 'sample_vendor' then s.row_data->>'sample_vendor' else s.row_data->>case when s.tracker_type='licensed' then 'U' else 'S' end end,
        'test_report', dam.orderlist_parse_boolean(case when s.row_data ? 'test_report' then s.row_data->>'test_report' else s.row_data->>case when s.tracker_type='licensed' then 'AI' else 'AE' end end),
        'professional_photos', dam.orderlist_parse_boolean(case when s.row_data ? 'professional_photos' then s.row_data->>'professional_photos' else s.row_data->>case when s.tracker_type='licensed' then 'AH' else 'AD' end end),
        'contractual_sample_reorder', case when s.tracker_type='licensed' then dam.orderlist_parse_boolean(case when s.row_data ? 'contractual_samples_reorder' then s.row_data->>'contractual_samples_reorder' else s.row_data->>'AO' end) else null end
      ) as facts
    from plm.style_tracker_item_bridge b
    join public.style_tracker_rows s on s.id=b.style_tracker_row_id
    where b.plm_item_id=p_item_id and (p_catalog is null or b.tracker_type=p_catalog)
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
  sent_to_coldlion boolean, worksheet_done boolean, inspection_passed date, inspection_note text,
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
returns void language plpgsql volatile security definer set search_path=pg_catalog,pg_temp as $$
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
returns void language plpgsql volatile security definer set search_path=pg_catalog,pg_temp as $$
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
returns uuid language plpgsql volatile security definer set search_path=pg_catalog,pg_temp as $$
declare
  v_key text;
  v_type text;
  v_header_keys text[] := array['sent_po_date','vendor_delivery_date','booking_state','etd','eta','container_booking_group','mbl','close_tracking'];
  v_extra_keys text[] := array['agent','cbm','comment','vessel','sent_to_coldlion','worksheet_done','inspection_passed','inspection_note','document_invoice','document_packing_list','document_bill_of_lading','document_tsca','document_lacey_act','document_telex','request_wire','payment_note'];
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
    v_type := case when v_key=any(array['sent_po_date','vendor_delivery_date','etd','eta','inspection_passed']) then 'date'
      when v_key='cbm' then 'numeric'
      when v_key=any(array['close_tracking','sent_to_coldlion','worksheet_done','document_invoice','document_packing_list','document_bill_of_lading','document_tsca','document_lacey_act','document_telex','request_wire']) then 'boolean'
      else 'text' end;
    if v_key=any(v_header_keys) then
      execute format('update plm.production_order set %I=$1::%s,updated_at=now() where id=$2',v_key,v_type)
        using case when v_type='text' then p_patch->>v_key else nullif(btrim(p_patch->>v_key),'') end,p_order_id;
    else
      execute format('update dam.order_tracking_ext set %I=$1::%s,updated_at=now(),updated_by=auth.uid() where order_id=$2',v_key,v_type)
        using case when v_type='text' then p_patch->>v_key else nullif(btrim(p_patch->>v_key),'') end,p_order_id;
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
    case when po.source_system='coldlion' and po.production_order_number like 'coldlion/%' then po.status else dam.orderlist_po_status(pol.order_type,pol.sku,pol.assortment_id,coalesce(pol.quantity_ordered,parent.quantity),pol.case_pack,po.close_tracking,po.booking_state,po.etd,coalesce(po.vendor_delivery_date,po.seal_container_date),po.sent_po_date,po.production_order_number) end AS order_status,
    po.company_id,
    coalesce(cust.customer_name,nullif(po.metadata->>'customer_name','')) AS customer_name,
    po.factory_id,
    coalesce(fact.vendor_name,nullif(po.metadata->>'order_vendor_name','')) AS vendor_name,
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
    coalesce(po.eta+5,po.warehouse_date) AS warehouse_date,
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
    coalesce(pol.metadata #>> '{order_list_source,sheet_row}',pol.metadata #>> '{order_list_snapshot,source_row}') AS snapshot_source_row,
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
    case when pol.case_pack=0 then 'Wrong Input' when pol.case_pack<0 then 'Wrong Input' when coalesce(pol.quantity_ordered,parent.quantity) is not null and pol.case_pack>coalesce(pol.quantity_ordered,parent.quantity) then 'Wrong QTY' end AS cases_error,
    parent.quantity AS assortment_parent_quantity,
    case when parent.physical_key is not null and parent.quantity>=pol.case_pack and pol.case_pack>0 then parent.quantity/pol.case_pack end AS assortment_parent_cases,
    parent.physical_key AS assortment_parent_key
   FROM plm.production_order_line pol
     JOIN plm.production_order po ON po.id = pol.production_order_id
     LEFT JOIN dam.dam_order_list_customer_directory cust ON cust.customer_id = po.company_id
     LEFT JOIN dam.dam_order_list_vendor_directory fact ON fact.vendor_id = po.factory_id
     LEFT JOIN plm.item item ON item.id = pol.item_id
     LEFT JOIN LATERAL (select dam.orderlist_product_facts(pol.item_id,pol.source_style_type) AS facts offset 0) product ON true
     LEFT JOIN LATERAL (
       select case when pol.assortment_component_ordinal is not null and pol.metadata #>> '{order_list_snapshot,component_quantity_source}'='absent_never_guessed'
         then dam.orderlist_parse_number(pol.metadata #>> '{order_list_snapshot,assortment_parent_quantity}') end as quantity,
         case when pol.assortment_component_ordinal is not null and pol.metadata #>> '{order_list_snapshot,component_quantity_source}'='absent_never_guessed'
           and nullif(pol.metadata #>> '{order_list_source,spreadsheet_id}','') is not null
           and nullif(pol.metadata #>> '{order_list_source,tab}','') is not null
           and nullif(pol.metadata #>> '{order_list_source,sheet_row}','') is not null
           then jsonb_build_array(pol.metadata #>> '{order_list_source,spreadsheet_id}',pol.metadata #>> '{order_list_source,tab}',pol.metadata #>> '{order_list_source,sheet_row}')::text end as physical_key
     ) parent ON true
     LEFT JOIN dam.orderlist_sample_depth sample ON sample.sku_normalized=pol.sku_normalized AND sample.customer_normalized=lower(btrim(coalesce(cust.customer_name,nullif(po.metadata->>'customer_name',''))))
     LEFT JOIN dam.orderlist_customer_settings customer_settings ON customer_settings.customer_normalized=lower(btrim(coalesce(cust.customer_name,nullif(po.metadata->>'customer_name',''))))
     LEFT JOIN plm.production_order_line_source_ref google_ref ON google_ref.production_order_line_id = pol.id AND google_ref.source_system = 'google_order_list'::text
     LEFT JOIN plm.production_order_line_source_ref coldlion_ref ON coldlion_ref.production_order_line_id = pol.id AND coldlion_ref.source_system = 'coldlion'::text;

-- Read and aggregate only the current PO's indexed lines. Expanded assortment
-- components retain unknown quantities; physical cases belong to the source parent.
create or replace view api.dam_order_tracking with (security_invoker=true) as
select po.id as order_id,po.production_order_number,po.order_date,po.voided_at as order_voided_at,
  coalesce(cust.customer_name,nullif(po.metadata->>'customer_name','')) as customer_name,coalesce(fact.vendor_name,nullif(po.metadata->>'order_vendor_name','')) as vendor_name,po.factory_id,po.company_id,
  lines.line_count,lines.total_cases,lines.invalid_case_lines,lines.missing_test_reports,lines.missing_photos,
  lines.unresolved_product_lines,lines.order_type,lines.start_ship_date,lines.cancel_date,lines.cargo_forecast_date,
  lines.customer_po_number,lines.customer_suffix,lines.components,
  po.sent_po_date,coalesce(po.vendor_delivery_date,po.seal_container_date) as vendor_delivery_date,
  case when coalesce(po.vendor_delivery_date,po.seal_container_date) is not null then coalesce(po.vendor_delivery_date,po.seal_container_date) +
    case lines.order_type when 'FOB' then 5 when 'POE' then 21 when 'C Stock' then 27 end end as seal_container_forecast,
  po.booking_state,po.etd,po.eta,coalesce(po.eta+5,po.warehouse_date) as warehouse_date,
  case when lines.order_type='FOB' then null
    when lines.order_type='POE' then po.eta-lines.cancel_date
    else coalesce(po.eta+5,po.warehouse_date)-lines.cancel_date end as days_delay,
  case when lines.order_type='POE' and coalesce(cust.customer_name,nullif(po.metadata->>'customer_name',''))='Burlington' and ext.worksheet_done is not true
    then po.eta-current_date-5 end as worksheet_days_remaining,
  po.container_booking_group,po.mbl,po.close_tracking,
  ext.agent,ext.cbm,ext.comment,ext.vessel,ext.sent_to_coldlion,ext.worksheet_done,ext.inspection_passed,ext.inspection_note,
  ext.document_invoice,ext.document_packing_list,ext.document_bill_of_lading,ext.document_tsca,ext.document_lacey_act,
  ext.document_telex,ext.request_wire,ext.payment_note,ext.updated_at as tracking_updated_at,
  case when ext.inspection_passed is not null then 'S'||(ext.inspection_passed-date '1899-12-30')::text||'-'||substring(po.production_order_number from 2) end as svn_number,
  case when left(po.container_booking_group,2)='BN' then po.container_booking_group||','||po.production_order_number end as booking_string,
  case when lines.order_type='FOB' then 'FOB' when lines.order_type='POE' and po.eta is null then 'no ETA'
    when lines.order_type is not null and lines.cancel_date is null then 'no cancel date'
    when lines.order_type is not null and po.eta is null then 'no WHS Date' end as days_delay_status,
  case when lines.order_type is not null and coalesce(po.vendor_delivery_date,po.seal_container_date) is null then 'No date' end as seal_container_forecast_status,lines.unknown_case_groups
from plm.production_order po
left join lateral (
  with scoped as materialized (
    select * from api.dam_order_list l where l.order_id=po.id and l.order_voided_at is null and l.line_voided_at is null
  ), physical as (
    select case when count(distinct case_pack)=1 and count(case_pack)=count(*)
        and count(distinct assortment_parent_quantity)=1 and count(assortment_parent_quantity)=count(*)
        and min(case_pack)>0 and min(assortment_parent_quantity)>=min(case_pack)
      then min(assortment_parent_quantity)/min(case_pack) end as cases
    from scoped where assortment_parent_key is not null
      and order_type is distinct from 'Contractual Sample' and order_type is distinct from 'David Sample'
    group by assortment_parent_key
    union all
    select cases_reported from scoped where assortment_parent_key is null
      and order_type is distinct from 'Contractual Sample' and order_type is distinct from 'David Sample'
  )
  select count(*) as line_count,
    (select case when count(cases)=count(*) then sum(cases) end from physical) as total_cases,
    (select count(*) from physical where cases is null) as unknown_case_groups,
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
      'professional_photos',professional_photos,'parent_cases',assortment_parent_cases,'sample_depth_inches',sample_depth_inches,'default_vendor',master_data_default_vendor,'sample_vendor',master_data_sample_vendor)
      order by assortment_id nulls last,assortment_component_ordinal nulls last,line_number,order_line_id) as components
  from scoped
) lines on true
left join dam.dam_order_list_customer_directory cust on cust.customer_id=po.company_id
left join dam.dam_order_list_vendor_directory fact on fact.vendor_id=po.factory_id
left join dam.order_tracking_ext ext on ext.order_id=po.id
where not (coalesce(po.source_system='coldlion',false) and coalesce(po.production_order_number like 'coldlion/%',false));

-- The native sheet's verified activity window is 14 months. Counts are PO
-- counts; sales-history quantities or stage rows are never summed as purchases.
create or replace view api.dam_order_vendor_statistics with (security_invoker=true) as
select factory_id,min(vendor_name) as vendor_name,count(*) as order_count,
  count(*) filter(where close_tracking is true) as closed_orders,
  count(*) filter(where close_tracking is not true and order_voided_at is null) as open_orders,
  max(sent_po_date) filter(where order_voided_at is null and production_order_number not ilike '%cancel%') as last_sent_po_date,
  case when max(sent_po_date) filter(where order_voided_at is null and production_order_number not ilike '%cancel%') > (current_date-interval '14 months')::date
    then 'Active' else 'Inactive' end as activity_status
from (
  select po.factory_id,coalesce(v.vendor_name,nullif(po.metadata->>'order_vendor_name','')) as vendor_name,
    po.close_tracking,po.voided_at as order_voided_at,po.sent_po_date,po.production_order_number
  from plm.production_order po left join dam.dam_order_list_vendor_directory v on v.vendor_id=po.factory_id
  where not(coalesce(po.source_system='coldlion',false) and coalesce(po.production_order_number like 'coldlion/%',false))
) headers
where vendor_name is not null
group by factory_id,lower(btrim(vendor_name));

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

-- The Master Data page uses the same status calculator as OrderList. A bounded
-- RPC avoids re-deriving the existing view and its unrelated ERP/RFQ joins.
create or replace function public.get_dam_style_tracker_license_status(p_row_ids uuid[])
returns table(id uuid,license_status text)
language plpgsql stable security invoker set search_path=pg_catalog,pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if cardinality(p_row_ids)>1000 then raise exception 'At most 1000 rows per request' using errcode='22023'; end if;
  return query select r.id,case when r.tracker_type='licensed'
    then dam.orderlist_license_status(r.row_data,r.discontinued) when r.tracker_type='generic' then 'Generic Item' else r.license_status end
    from public.style_tracker_rows r where r.id=any(p_row_ids);
end;
$$;
revoke all on function public.get_dam_style_tracker_license_status(uuid[]) from public,anon;
grant execute on function public.get_dam_style_tracker_license_status(uuid[]) to authenticated;

-- Materialize a bounded header page before any line facts or component JSON.
create or replace function public.get_dam_order_tracking(p_offset integer default 0,p_limit integer default 100,p_search text default null,p_only_open boolean default false)
returns setof api.dam_order_tracking language plpgsql stable security invoker set search_path=pg_catalog,pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_offset is null or p_offset<0 or p_limit is null or p_limit<1 or p_limit>200 then
    raise exception 'Tracking requests require a nonnegative offset and 1 to 200 orders' using errcode='22023';
  end if;
  if length(p_search)>200 then raise exception 'Search is limited to 200 characters' using errcode='22023'; end if;
  return query with page as materialized (
    select po.id,po.order_date,po.production_order_number from plm.production_order po
    where not(coalesce(po.source_system='coldlion',false) and coalesce(po.production_order_number like 'coldlion/%',false))
      and (p_only_open is not true or (po.close_tracking is not true and po.voided_at is null))
      and (nullif(btrim(p_search),'') is null or po.production_order_number ilike '%'||p_search||'%'
        or po.metadata->>'customer_name' ilike '%'||p_search||'%' or po.metadata->>'order_vendor_name' ilike '%'||p_search||'%')
    order by po.order_date desc nulls last,po.production_order_number,po.id limit p_limit offset p_offset
  ) select t.* from page p cross join lateral (select * from api.dam_order_tracking t where t.order_id=p.id offset 0) t
    order by p.order_date desc nulls last,p.production_order_number,p.id;
end;
$$;
revoke all on function public.get_dam_order_tracking(integer,integer,text,boolean),dam.orderlist_parse_number(text) from public,anon;
grant execute on function public.get_dam_order_tracking(integer,integer,text,boolean) to authenticated;
grant execute on function dam.orderlist_parse_number(text) to authenticated,service_role;

do $verify$
declare object_name text; signature text; table_name text; policy_name text;
begin
  foreach object_name in array array['api.dam_order_list','api.dam_order_tracking','api.dam_order_vendor_statistics','api.dam_order_sample_depth','api.dam_order_customer_settings'] loop
    if to_regclass(object_name) is null or not has_table_privilege('authenticated',object_name,'select') or has_table_privilege('anon',object_name,'select') then
      raise exception 'Missing or unsafe serving view %',object_name;
    end if;
  end loop;
  foreach table_name in array array['order_tracking_ext','orderlist_sample_depth','orderlist_customer_settings'] loop
    if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='dam' and c.relname=table_name and c.relrowsecurity)
      or not has_table_privilege('authenticated','dam.'||table_name,'select')
      or has_table_privilege('anon','dam.'||table_name,'select') then raise exception 'Missing RLS or unsafe table %',table_name; end if;
    foreach policy_name in array array[table_name||'_read',table_name||'_write'] loop
      if not exists(select 1 from pg_policies p where p.schemaname='dam' and p.tablename=table_name and p.policyname=policy_name) then
        raise exception 'Missing policy %',policy_name;
      end if;
    end loop;
  end loop;
  foreach signature in array array['dam.orderlist_parse_number(text)','dam.orderlist_parse_boolean(text)','dam.orderlist_license_status(jsonb,boolean)',
    'dam.orderlist_po_status(text,text,text,numeric,numeric,boolean,text,date,date,date,text)','dam.orderlist_cargo_forecast(text,text,date)',
    'dam.orderlist_product_facts(uuid,text)','public.update_dam_order_tracking(uuid,jsonb)','public.upsert_dam_order_sample_depth(text,text,numeric)',
    'public.upsert_dam_order_customer_settings(text,text)','public.get_dam_style_tracker_license_status(uuid[])','public.get_dam_order_tracking(integer,integer,text,boolean)'] loop
    if to_regprocedure(signature) is null or not has_function_privilege('authenticated',signature,'execute') or has_function_privilege('anon',signature,'execute') then
      raise exception 'Missing or unsafe function %',signature;
    end if;
  end loop;
end;
$verify$;

notify pgrst,'reload schema';
commit;
