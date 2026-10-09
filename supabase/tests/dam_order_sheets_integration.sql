-- Run on an isolated integration database or governed PREVIEW, never production.
-- Fixtures and edits are always rolled back. Unknowns remain unknown.
begin;

do $tests$
declare actual text;
begin
  if dam.orderlist_parse_boolean('FALSE') is distinct from false
    or dam.orderlist_parse_boolean(' TRUE ') is distinct from true
    or dam.orderlist_parse_boolean('pending') is not null
    or dam.orderlist_parse_boolean(null) is not null then
    raise exception 'Boolean status parsing lost false or invented a result';
  end if;
  if dam.orderlist_license_status('{}',false)<>'No Info'
    or dam.orderlist_license_status('{"R":"2026-01-01"}',false)<>'Concept Approved'
    or dam.orderlist_license_status('{"concept_approval":"2026-01-01","production_approval":"2026-02-01"}',false)<>'Production Approved'
    or dam.orderlist_license_status('{"AC":"2026-02-01"}',true)<>'Discontinue' then
    raise exception 'Licensed status priority differs from source milestone logic';
  end if;
  if dam.orderlist_cargo_forecast('C Stock','NJ','2026-02-20') is distinct from date '2026-01-14'
    or dam.orderlist_cargo_forecast('FOB','NJ','2026-02-20') is distinct from date '2026-02-13'
    or dam.orderlist_cargo_forecast('POE','CA','2026-02-20') is distinct from date '2026-01-28'
    or dam.orderlist_cargo_forecast('POE','UNKNOWN','2026-02-20') is not null then
    raise exception 'Cargo forecasts must calculate each line independently';
  end if;
  actual:=dam.orderlist_po_status('FOB','TEST-SKU',null,12,6,false,'Booked',null,null,null,'TEST-PO');
  if actual<>'Booked FOB' then raise exception 'FOB booking priority failed'; end if;
  actual:=dam.orderlist_po_status('POE','TEST-SKU',null,12,6,false,'Booked','2026-01-01',null,null,'TEST-PO');
  if actual<>'Confirmed Booking' then raise exception 'ETD must outrank booking state'; end if;
  actual:=dam.orderlist_po_status('POE','TEST-SKU',null,12,6,true,'Booked','2026-01-01',null,null,'TEST-PO');
  if actual<>'Close tracking' then raise exception 'Closed tracking must outrank shipping states'; end if;
  if has_function_privilege('anon','public.update_dam_order_tracking(uuid,jsonb)','execute')
    or has_table_privilege('anon','api.dam_order_tracking','select') then
    raise exception 'Anonymous access is forbidden';
  end if;
end;
$tests$;

create temp table integration_ids(key text primary key,id uuid default gen_random_uuid());
insert into integration_ids(key) values('item'),('licensed'),('duplicate'),('generic'),('order'),('line'),('sample-line'),('coldlion-order'),('coldlion-line');

insert into plm.item(id,item_number,description,name,source_system,source_id)
select id,'TEST-INTEGRATION-SKU','Canonical Item Master description','Canonical name','integration_test','integration-fixture-item' from integration_ids where key='item';
insert into public.style_tracker_rows(id,source_workbook_id,source_sheet,source_row_number,tracker_type,description,license_status,default_vendor,discontinued,row_data)
select id,'integration-test','License.Style',900001,'licensed','Outdated tracker description','Outdated cached status','TEST-PRIMARY-VENDOR',false,
  '{"sample_vendor":"TEST-SAMPLE-VENDOR","professional_photos":true,"test_report":false,"contractual_samples_reorder":true,"concept_approval":"2026-01-01"}'::jsonb
from integration_ids where key='licensed';
insert into plm.style_tracker_item_bridge(style_tracker_row_id,source_workbook_id,source_sheet,tracker_type,plm_item_id)
select s.id,'integration-test','License.Style','licensed',i.id from integration_ids s cross join integration_ids i where s.key='licensed' and i.key='item';
insert into plm.production_order(id,production_order_number,sent_po_date,eta,close_tracking)
select id,'TEST-INTEGRATION-PO',current_date,'2026-04-10',false from integration_ids where key='order';
insert into plm.production_order_line(id,production_order_id,item_id,sku,quantity_ordered,case_pack,order_type,source_style_type,test_report,professional_photos)
select l.id,o.id,i.id,'TEST-INTEGRATION-SKU',24,6,'POE','licensed','true','false'
from integration_ids l cross join integration_ids o cross join integration_ids i where l.key='line' and o.key='order' and i.key='item';
insert into plm.production_order_line(id,production_order_id,sku,quantity_ordered,case_pack,order_type)
select l.id,o.id,'TEST-SAMPLE-SKU',6,6,'Contractual Sample'
from integration_ids l cross join integration_ids o where l.key='sample-line' and o.key='order';

do $tests$
declare r record; tracking record;
begin
  select * into strict r from api.dam_order_list where order_line_id=(select id from integration_ids where key='line');
  if r.item_description<>'Canonical Item Master description' or r.master_data_description<>'Canonical Item Master description'
    or r.master_data_license_status<>'Concept Approved' or r.test_report<>'false' or r.professional_photos<>'true'
    or r.master_data_sample_vendor<>'TEST-SAMPLE-VENDOR' or r.contractual_sample_reorder is distinct from true
    or r.cases_reported<>4 then raise exception 'Live Master Data outputs or computed cases failed'; end if;
  select * into strict tracking from api.dam_order_tracking where order_id=r.order_id;
  if tracking.total_cases<>4 or tracking.line_count<>2 or tracking.missing_test_reports<>2
    or tracking.missing_photos<>1 or tracking.warehouse_date<>date '2026-04-15' then
    raise exception 'PO aggregate duplicated components or lost missing-value warnings';
  end if;
  -- Clearing a current status must not resurrect the imported value.
  update public.style_tracker_rows set row_data=row_data||'{"test_report":null,"professional_photos":false,"production_approval":"2026-03-01"}'::jsonb
    where id=(select id from integration_ids where key='licensed');
  select * into strict r from api.dam_order_list where order_line_id=r.order_line_id;
  if r.test_report is not null or r.professional_photos<>'false' or r.master_data_license_status<>'Production Approved' then
    raise exception 'Current edits/clears must reach OrderList without rewriting order lines';
  end if;
  if (select test_report from plm.production_order_line where id=r.order_line_id)<>'true' then
    raise exception 'Integration must not rewrite historical imported facts';
  end if;
end;
$tests$;

-- Two conflicting tracker rows linked to one item must become a visible unknown,
-- not two order rows or an arbitrary selected product value.
insert into public.style_tracker_rows(id,source_workbook_id,source_sheet,source_row_number,tracker_type,description,license_status,default_vendor,discontinued,row_data)
select id,'integration-test','License.Style',900002,'licensed','Another tracker','No Info','OTHER-VENDOR',false,'{}'::jsonb from integration_ids where key='duplicate';
insert into plm.style_tracker_item_bridge(style_tracker_row_id,source_workbook_id,source_sheet,tracker_type,plm_item_id)
select s.id,'integration-test','License.Style','licensed',i.id from integration_ids s cross join integration_ids i where s.key='duplicate' and i.key='item';
do $tests$
declare r record;
begin
  select * into strict r from api.dam_order_list where order_line_id=(select id from integration_ids where key='line');
  if r.product_workflow_source<>'ambiguous' or r.master_data_default_vendor is not null or r.test_report is not null
    or r.item_description<>'Canonical Item Master description' then
    raise exception 'Conflicting tracker facts must abstain while preserving the canonical item';
  end if;
end;
$tests$;

insert into plm.production_order(id,production_order_number,source_system)
select id,'coldlion/SO-TEST','coldlion' from integration_ids where key='coldlion-order';
do $tests$
begin
  if exists(select 1 from api.dam_order_tracking where order_id=(select id from integration_ids where key='coldlion-order')) then
    raise exception 'Sales-history placeholders are not production PO tracking records';
  end if;
end;
$tests$;

-- The write guards must actually fire, not merely be present in source text.
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000000001';
do $tests$
begin
  begin
    perform public.update_dam_order_tracking((select id from integration_ids where key='order'),'{}');
    raise exception 'A normal user unexpectedly changed PO tracking';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.upsert_dam_order_sample_depth('TEST-SKU','TEST-CUSTOMER',1);
    raise exception 'A normal user unexpectedly changed sample depth';
  exception when insufficient_privilege then null;
  end;
end;
$tests$;

set local request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000001","app_metadata":{"roles":["administrator"]}}';
do $tests$
declare v_order_id uuid := (select id from integration_ids where key='order'); r record;
begin
  perform public.update_dam_order_tracking(v_order_id,'{"sent_po_date":"2026-03-01","vendor_delivery_date":"2026-03-15","booking_state":"Booked","etd":"2026-03-20","comment":"Reviewed fixture","worksheet_done":true}');
  select * into strict r from api.dam_order_tracking where api.dam_order_tracking.order_id=v_order_id;
  if r.sent_po_date<>date '2026-03-01' or r.comment<>'Reviewed fixture' or r.worksheet_done is distinct from true then
    raise exception 'Administrator tracking edit did not persist atomically';
  end if;
  perform public.update_dam_order_tracking(v_order_id,'{"comment":null}');
  select * into strict r from api.dam_order_tracking where api.dam_order_tracking.order_id=v_order_id;
  if r.comment is not null or r.sent_po_date<>date '2026-03-01' then
    raise exception 'Explicit clearing must preserve omitted fields';
  end if;
  begin
    perform public.update_dam_order_tracking(v_order_id,'{"production_order_number":"WRONG"}');
    raise exception 'Tracking unexpectedly changed protected identity';
  exception when insufficient_privilege then null; end;
  begin
    perform public.update_dam_order_tracking(v_order_id,'{"comment":"Must roll back","eta":"not-a-date"}');
    raise exception 'Invalid tracking date was accepted';
  exception when invalid_datetime_format then null; end;
  if exists(select 1 from api.dam_order_tracking where api.dam_order_tracking.order_id=v_order_id and comment='Must roll back') then
    raise exception 'Failed tracking patch partially wrote other fields';
  end if;
  if (select license_status from public.get_dam_style_tracker_license_status(array[(select id from integration_ids where key='licensed')]))<>'Production Approved' then
    raise exception 'Master Data and OrderList must use the same live milestone status';
  end if;
  begin
    perform public.get_dam_style_tracker_license_status(array_fill(v_order_id,array[1001]));
    raise exception 'Master status request exceeded bounded capacity';
  exception when invalid_parameter_value then null; end;
  perform public.upsert_dam_order_sample_depth(' Test-SKU ',' Test-Customer ',1.5);
  if not exists(select 1 from api.dam_order_sample_depth where sku_normalized='test-sku' and customer_normalized='test-customer' and depth_inches=1.5) then
    raise exception 'Customer-specific sample depth normalized incorrectly';
  end if;
  perform public.upsert_dam_order_customer_settings(' Test-Customer ','TEST');
  if not exists(select 1 from api.dam_order_customer_settings where customer_normalized='test-customer' and suffix='TEST') then
    raise exception 'Customer suffix did not persist';
  end if;
end;
$tests$;

rollback;
