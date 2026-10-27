-- #4858: unlike component quantities, physical cartons must not be summed.
begin;

insert into plm.production_order(id,production_order_number,source_system,source_id,metadata)
values ('48580000-0000-4000-8000-000000000001','TEST-COLDLION-CASEPACK-4858','coldlion','test-casepack-4858',
        '{"customer_name":"Test case pack"}');

insert into plm.production_order_line
 (id,production_order_id,sku,quantity_ordered,case_pack,order_type,source_system,source_id,
  assortment_id,assortment_component_ordinal,metadata)
values
 ('48580000-0000-4000-8000-000000000011','48580000-0000-4000-8000-000000000001','TEST-PACK-A',120,1,'FOB','coldlion',
  'coldlion:so:1900004858:line:1:component:1','TEST-ASSORTMENT',1,'{"line_qty":480,"master_item_no":"TEST-ASSORTMENT"}'),
 ('48580000-0000-4000-8000-000000000012','48580000-0000-4000-8000-000000000001','TEST-PACK-B',240,2,'FOB','coldlion',
  'coldlion:so:1900004858:line:1:component:2','TEST-ASSORTMENT',2,'{"line_qty":480,"master_item_no":"TEST-ASSORTMENT"}'),
 ('48580000-0000-4000-8000-000000000013','48580000-0000-4000-8000-000000000001','TEST-PACK-C',120,1,'FOB','coldlion',
  'coldlion:so:1900004858:line:1:component:3','TEST-ASSORTMENT',3,'{"line_qty":480,"master_item_no":"TEST-ASSORTMENT"}'),
 ('48580000-0000-4000-8000-000000000014','48580000-0000-4000-8000-000000000001','TEST-DIRECT-PACK',12,4,'FOB','coldlion',
  'coldlion:so:1900004858:line:2:component:1',null,null,'{"line_qty":12,"master_item_no":"TEST-DIRECT-PACK"}');

do $tests$
declare n integer; t record;
begin
  select count(distinct assortment_parent_key) into n from api.dam_order_list
   where order_id='48580000-0000-4000-8000-000000000001' and assortment_component_ordinal is not null;
  if n<>1 then raise exception 'Three component designs must share one physical carton group'; end if;
  select count(*) into n from api.dam_order_list
   where order_id='48580000-0000-4000-8000-000000000001' and assortment_component_ordinal is not null
     and assortment_parent_quantity=480 and assortment_parent_cases=120 and cases_reported=120;
  if n<>3 then raise exception 'Each design must yield the same 120 physical cartons despite unequal packs'; end if;
  select * into strict t from dam.dam_order_tracking where order_id='48580000-0000-4000-8000-000000000001';
  if t.total_cases is distinct from 123::numeric or t.unknown_case_groups<>0 then
    raise exception 'Expected 120 assortment cartons plus 3 direct-item cartons, got %',t.total_cases; end if;
end;
$tests$;

-- Conflicting per-design carton counts must stay explicitly unknown.
update plm.production_order_line set case_pack=3 where id='48580000-0000-4000-8000-000000000012';
do $tests$
declare t record;
begin
  select * into strict t from dam.dam_order_tracking where order_id='48580000-0000-4000-8000-000000000001';
  if t.total_cases is not null or t.unknown_case_groups<>1 then
    raise exception 'Inconsistent design counts must not publish a complete carton total'; end if;
end;
$tests$;

update plm.production_order_line set case_pack=null where id='48580000-0000-4000-8000-000000000012';
do $tests$
declare t record;
begin
  select * into strict t from dam.dam_order_tracking where order_id='48580000-0000-4000-8000-000000000001';
  if t.total_cases is not null or t.unknown_case_groups<>1 then
    raise exception 'Missing design pack must keep the physical group unknown'; end if;
end;
$tests$;

-- Existing Google/manual assortment behavior is independently covered by
-- dam_order_sheets_integration.sql, including differing parent packs.
rollback;
