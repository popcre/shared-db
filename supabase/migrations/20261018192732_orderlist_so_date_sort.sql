-- Work issue #4336; exact object claim #4471 (version 20261018192732).
-- derived-from: 20261009073649
-- Full-result OrderList SO received date for sorting only; Find uses the same sort key.
-- The date rule is unchanged from public.get_dam_order_sales_order_dates: exact primary
-- ColdLion references, company EDGEHOME, one non-null full timestamp per Sales Order,
-- America/New_York date. Missing or conflicting stamps stay blank.
begin;

do $dependencies$
declare column_check record;
begin
  if not exists (
    select 1 from pg_catalog.pg_class c
    where c.oid=to_regclass('api.dam_order_list') and c.relkind='v'
      and c.reloptions @> array['security_invoker=true']
  ) then
    raise exception '#4336 requires the security-invoker OrderList view';
  end if;
  for column_check in select * from (values
    ('api.dam_order_list','order_line_id','uuid'),
    ('api.dam_order_list','coldlion_source_id','text'),
    ('coldlion.order_history_line','company_code','text'),
    ('coldlion.order_history_line','sales_order_no','bigint'),
    ('coldlion.order_history_line','created_time','timestamp with time zone'),
    ('plm.production_order_line','id','uuid'),
    ('plm.production_order_line_source_ref','production_order_line_id','uuid'),
    ('plm.production_order_line_source_ref','source_system','text'),
    ('plm.production_order_line_source_ref','source_id','text'),
    ('plm.production_order_line_source_ref','is_primary','boolean')
  ) expected(object_name,column_name,type_name)
  loop
    if not exists (
      select 1 from pg_catalog.pg_attribute a
      where a.attrelid=to_regclass(column_check.object_name)
        and a.attname=column_check.column_name and not a.attisdropped
        and a.atttypid=to_regtype(column_check.type_name)
    ) then
      raise exception '#4336 dependency missing or changed: %.% (%)',
        column_check.object_name,column_check.column_name,column_check.type_name;
    end if;
  end loop;
  if to_regprocedure('auth.uid()') is null
     or to_regprocedure('auth.role()') is null then
    raise exception '#4336 requires auth.uid() and auth.role() for the SO-date helper access gate';
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    join pg_catalog.pg_attribute id_column
      on id_column.attrelid=constraint_row.conrelid
     and id_column.attname='id'
     and not id_column.attisdropped
    where constraint_row.conrelid=to_regclass('plm.production_order_line')
      and constraint_row.contype='p'
      and constraint_row.conkey=array[id_column.attnum]::smallint[]
  ) then
    raise exception '#4336 requires the production-order-line primary key used by exact source binding';
  end if;
  if position('coldlion_ref.is_primary' in lower(pg_get_viewdef('api.dam_order_list'::regclass)))=0 then
    raise exception '#4336 requires primary-only ColdLion references in OrderList';
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_index i
    join pg_catalog.pg_class idx on idx.oid=i.indexrelid
    join pg_catalog.pg_attribute a on a.attrelid=i.indrelid and a.attname='sales_order_no' and not a.attisdropped
    where i.indrelid=to_regclass('coldlion.order_history_line')
      and idx.relname='coldlion_order_history_line_identity_unique'
      and i.indisunique and i.indisvalid and i.indisready
      and i.indnkeyatts=4
      and i.indkey[0]=a.attnum
  ) then
    raise exception '#4336 requires the valid sales_order_no-leading history identity index';
  end if;
  if not exists (
    select 1
    from pg_catalog.pg_index i
    join pg_catalog.pg_class idx on idx.oid=i.indexrelid
    join pg_catalog.pg_attribute line_id on line_id.attrelid=i.indrelid and line_id.attname='production_order_line_id' and not line_id.attisdropped
    join pg_catalog.pg_attribute source_system on source_system.attrelid=i.indrelid and source_system.attname='source_system' and not source_system.attisdropped
    where i.indrelid=to_regclass('plm.production_order_line_source_ref')
      and idx.relname='production_order_line_source_ref_primary_uidx'
      and i.indisunique and i.indisvalid and i.indisready
      and i.indnkeyatts=2
      and i.indkey[0]=line_id.attnum and i.indkey[1]=source_system.attnum
      and pg_get_expr(i.indpred,i.indrelid) ilike '%is_primary%'
  ) then
    raise exception '#4336 requires the valid primary-only OrderList source-reference index';
  end if;
end;
$dependencies$;

create or replace function dam.orderlist_sales_order_received_date(
  p_order_line_id uuid,
  p_coldlion_source_id text
)
returns date
language sql stable strict security definer
set search_path = pg_catalog
as $$
  select case when auth.uid() is not null or auth.role() = 'service_role' then (
    select case when count(*) = count(h.created_time)
      and count(distinct h.created_time) = 1
      and min(h.created_time) > timestamptz '2000-01-01 00:00:00+00'
    then (min(h.created_time) at time zone 'America/New_York')::date end
    from coldlion.order_history_line h
    where h.company_code = 'EDGEHOME'
      and h.sales_order_no = case
        when p_coldlion_source_id ~ '^coldlion:so:[1-9][0-9]{0,17}:line:[0-9]{1,10}:component:[1-9][0-9]{0,9}$'
        then split_part(p_coldlion_source_id, ':', 3)::bigint end
      and exists (
        select 1
        from plm.production_order_line pol
        join plm.production_order_line_source_ref source_ref
          on source_ref.production_order_line_id=pol.id
         and source_ref.source_system='coldlion'
         and source_ref.is_primary
         and source_ref.source_id=p_coldlion_source_id
        where pol.id=p_order_line_id
      )
  ) end
$$;

revoke all on function dam.orderlist_sales_order_received_date(uuid,text) from public, anon;
grant execute on function dam.orderlist_sales_order_received_date(uuid,text) to authenticated, service_role;
comment on function dam.orderlist_sales_order_received_date(uuid,text) is
  'OrderList SO received date only for an authenticated caller (or service_role) and an exact primary ColdLion source reference bound to its canonical order line; this does not expose an arbitrary SO-number date oracle. The date uses the same EDGEHOME/full-timestamp/America-New_York rule as get_dam_order_sales_order_dates. #4336.';

create or replace view api.dam_order_list with (security_invoker=true) as
SELECT pol.id AS order_line_id,
    po.id AS order_id,
    po.production_order_number,
    case when po.source_system='coldlion' and po.production_order_number like 'coldlion/%' then po.status else dam.orderlist_po_status(pol.order_type,pol.sku,pol.assortment_id,coalesce(pol.quantity_ordered,parent.quantity),pol.case_pack,po.close_tracking,po.booking_state,po.etd,case when ext.crd_override_set then po.vendor_delivery_date else coalesce(po.vendor_delivery_date,po.seal_container_date) end,po.sent_po_date,po.production_order_number) end AS order_status,
    po.company_id,
    coalesce(cust.customer_name,nullif(po.metadata->>'customer_name','')) AS customer_name,
    po.factory_id,
    coalesce(fact.vendor_name,nullif(po.metadata->>'order_vendor_name','')) AS vendor_name,
    po.metadata ->> 'ordering_company'::text AS ordering_company,
    po.order_date,
    po.sent_po_date,
    case when ext.crd_override_set then po.vendor_delivery_date else coalesce(po.vendor_delivery_date,po.seal_container_date) end AS seal_container_date,
    po.vendor_delivery_date,
    po.requested_ship_date,
    po.actual_ship_date,
    po.booking_state,
    po.etd,
    po.eta,
    case when ext.eta_override_set then po.eta+5 else coalesce(po.eta+5,po.warehouse_date) end AS warehouse_date,
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
    parent.physical_key AS assortment_parent_key,
    sample.depth_raw AS sample_depth_raw,
    sample.source_row_number AS sample_depth_source_row,
    pol.test_report AS snapshot_test_report,
    pol.professional_photos AS snapshot_professional_photos,
    pol.contractual_sample_reorder AS snapshot_contractual_sample_reorder,
    so_date.sales_order_received_date
   FROM plm.production_order_line pol
     JOIN plm.production_order po ON po.id = pol.production_order_id
     LEFT JOIN dam.dam_order_list_customer_directory cust ON cust.customer_id = po.company_id
     LEFT JOIN dam.dam_order_list_vendor_directory fact ON fact.vendor_id = po.factory_id
     LEFT JOIN dam.order_tracking_ext ext ON ext.order_id=po.id
     LEFT JOIN plm.item item ON item.id = pol.item_id
     LEFT JOIN LATERAL (select (select f.facts from dam.orderlist_product_facts(pol.item_id,pol.source_style_type) f) as facts offset 0) product ON true
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
     LEFT JOIN plm.production_order_line_source_ref google_ref ON google_ref.production_order_line_id = pol.id AND google_ref.source_system = 'google_order_list'::text AND google_ref.is_primary
     LEFT JOIN plm.production_order_line_source_ref coldlion_ref ON coldlion_ref.production_order_line_id = pol.id AND coldlion_ref.source_system = 'coldlion'::text AND coldlion_ref.is_primary
     LEFT JOIN LATERAL (select dam.orderlist_sales_order_received_date(pol.id,coldlion_ref.source_id) AS sales_order_received_date) so_date ON true;

create or replace function public.find_dam_order_list_row(
  p_search text,
  p_filters jsonb default '[]'::jsonb,
  p_sort jsonb default '[]'::jsonb
) returns table(order_line_id uuid, row_index bigint)
language plpgsql stable security invoker
set search_path = pg_catalog, auth
as $function$
declare
  allowed_columns constant text[] := array[
    'order_line_id','order_status','production_order_number','vendor_name',
    'order_date','sent_po_date','customer_name','customer_po_number','sku',
    'master_data_match_status','master_data_description','master_data_license_status',
    'master_data_licensor','source_style_type','quantity_ordered','case_pack',
    'start_ship_date','cancel_date','requested_ship_date','actual_ship_date','etd',
    'eta','warehouse_date','container_booking_group','mbl','close_tracking',
    'line_number','order_person','order_type','customer_suffix','ordering_company',
    'assortment_id','assortment_component_ordinal','quantity_shipped','unit_cost',
    'order_depth_inches','cases_reported','ship_to','cargo_forecast_date',
    'start_ship_raw','cancel_raw','cargo_forecast_raw','seal_container_date',
    'vendor_delivery_date','booking_state','test_report','professional_photos',
    'contractual_sample_reorder','line_status','master_data_default_vendor',
    'master_data_customer','item_number','item_style_number','snapshot_description',
    'snapshot_license_status','snapshot_sku','snapshot_source_row','google_source_id',
    'coldlion_source_id','order_void_reason','line_void_reason'
  ];
  sort_only_columns constant text[] := array['sales_order_received_date'];
  spec jsonb;
  col text;
  op text;
  sql_op text;
  predicates text := 'true';
  ordering text := '';
  pattern text;
begin
  if auth.uid() is null or auth.role() is distinct from 'authenticated' then
    raise insufficient_privilege using message = 'Authenticated access required';
  end if;
  p_filters := coalesce(p_filters, '[]'::jsonb);
  p_sort := coalesce(p_sort, '[]'::jsonb);
  if jsonb_typeof(p_filters) <> 'array' or jsonb_typeof(p_sort) <> 'array' then
    raise invalid_parameter_value using message = 'Filters and sort must be normalized arrays';
  end if;
  for spec in select value from jsonb_array_elements(p_filters) loop
    if jsonb_typeof(spec) <> 'object' then
      raise invalid_parameter_value using message = 'Invalid normalized filter';
    end if;
    col := spec->>'column'; op := spec->>'operator';
    if col is null or not (col = any(allowed_columns))
       or op is null or op not in ('eq','neq','gt','gte','lt','lte','ilike','not.ilike','is','not.is')
       or not (spec ? 'value')
       or exists(select 1 from jsonb_object_keys(spec) k where k not in ('column','operator','value')) then
      raise invalid_parameter_value using message = 'Unsupported normalized filter';
    end if;
    if op in ('is','not.is') then
      if spec->'value' <> 'null'::jsonb then
        raise invalid_parameter_value using message = 'Null filter requires a null value';
      end if;
      predicates := predicates || format(' and d.%I is %snull', col, case when op='not.is' then 'not ' else '' end);
    else
      if jsonb_typeof(spec->'value') not in ('string','number','boolean') then
        raise invalid_parameter_value using message = 'Comparison filter requires a scalar value';
      end if;
      sql_op := case op when 'eq' then '=' when 'neq' then '<>' when 'gt' then '>'
        when 'gte' then '>=' when 'lt' then '<' when 'lte' then '<='
        when 'ilike' then 'ilike' when 'not.ilike' then 'not ilike' end;
      -- %I quotes an allowlisted identifier; %L quotes a value. The unknown SQL
      -- literal is coerced to the view column's native type, as PostgREST does.
      -- Normalized ilike values already contain PopDAM's literal escaping.
      predicates := predicates || format(' and d.%I %s %L', col, sql_op, spec->>'value');
    end if;
  end loop;
  for spec in select value from jsonb_array_elements(p_sort) loop
    if jsonb_typeof(spec) <> 'object' then
      raise invalid_parameter_value using message = 'Invalid normalized sort';
    end if;
    col := spec->>'column';
    if col is null or not (col = any(allowed_columns) or col = any(sort_only_columns))
       or jsonb_typeof(spec->'ascending') is distinct from 'boolean'
       or exists(select 1 from jsonb_object_keys(spec) k where k not in ('column','ascending')) then
      raise invalid_parameter_value using message = 'Unsupported normalized sort';
    end if;
    ordering := ordering || format('d.%I %s nulls last, ', col,
      case when (spec->>'ascending')::boolean then 'asc' else 'desc' end);
  end loop;
  if ordering = '' then ordering := 'd.order_date desc nulls last, '; end if;
  ordering := ordering || 'd.order_line_id asc nulls last';
  -- ECMAScript String.trim whitespace, matching PopDAM rather than just ASCII space.
  p_search := btrim(p_search, U&'\0009\000A\000B\000C\000D\0020\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF');
  if p_search is null or p_search = '' then return; end if;
  pattern := '%' || replace(replace(replace(p_search, chr(92), chr(92)||chr(92)),
    '%', chr(92)||'%'), '_', chr(92)||'_') || '%';
  return query execute format($query$
    with ranked as materialized (
      select d.order_line_id, row_number() over(order by %s) - 1 as row_index,
        (d.production_order_number ilike $1 or d.order_status ilike $1
         or d.customer_po_number ilike $1 or d.sku ilike $1
         or d.vendor_name ilike $1 or d.customer_name ilike $1
         or d.container_booking_group ilike $1 or d.mbl ilike $1
         or d.snapshot_description ilike $1) as matches
      from api.dam_order_list d where %s
    )
    select r.order_line_id, r.row_index from ranked r
    where r.matches order by r.row_index limit 1
  $query$, ordering, predicates) using pattern;
end;
$function$;
revoke all on function public.find_dam_order_list_row(text,jsonb,jsonb) from public, anon, service_role;
grant execute on function public.find_dam_order_list_row(text,jsonb,jsonb) to authenticated;
comment on function public.find_dam_order_list_row(text,jsonb,jsonb) is
  'Authenticated invoker-only OrderList Find: normalized PopDAM filters/sorts; SO received date is sort-only; first literal search match and zero-based position within the full filtered grid.';

commit;
