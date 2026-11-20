-- Real view-backed fixtures, rolled back; never run this against production.
begin;
do $$
declare item uuid; ord uuid; before_counts jsonb; after_counts jsonb; suffix text:=txid_current()::text;
begin
  before_counts:=public.get_dam_order_list_status_counts();
  insert into plm.item(item_number,style_number,name,source_system,source_id)
  values('ZZ-AUDIT-COUNT-'||suffix,'ZZ-AUDIT-COUNT-'||suffix,'Synthetic audit count item','audit_count_boundary',suffix)
  returning id into item;
  insert into plm.production_order(production_order_number,status,source_system,source_id)
  values('ZZ-AUDIT-COUNT-'||suffix,'Open','audit_count_boundary',suffix) returning id into ord;
  -- The source does not permit NULL statuses, even before counting through the API view.
  begin
    insert into plm.production_order_line(production_order_id,line_number,sku,quantity_ordered,master_data_match_status,source_system,source_id)
    values(ord,'NULL','ZZ-AUDIT-COUNT-'||suffix,1,null,'audit_count_boundary',suffix||'-null');
    raise exception 'NULL source status unexpectedly accepted';
  exception when not_null_violation then null;
  end;
  insert into plm.production_order_line(production_order_id,line_number,sku,quantity_ordered,item_id,master_data_match_status,source_system,source_id)
  select ord,n::text,'ZZ-AUDIT-COUNT-'||suffix,1,
    case when status in ('matched','manual') then item else null end,
    status,'audit_count_boundary',suffix||'-'||n
  from (values(1,'not_applicable'),(2,'unmatched'),(3,'ambiguous'),(4,'matched'),(5,'manual')) s(n,status);
  after_counts:=public.get_dam_order_list_status_counts();
  if (after_counts->>'total')::bigint-(before_counts->>'total')::bigint<>5
    or (after_counts->>'linked')::bigint-(before_counts->>'linked')::bigint<>2
    or (after_counts->>'ambiguous')::bigint-(before_counts->>'ambiguous')::bigint<>1
    or (after_counts->>'unmatched')::bigint-(before_counts->>'unmatched')::bigint<>1 then
    raise exception 'view-backed count boundary changed: before %, after %',before_counts,after_counts;
  end if;
end $$;
rollback;
