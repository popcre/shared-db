-- Source-only reader proof; business-specific row/UI acceptance stays on app issues.
select
  to_regprocedure('public.get_dam_order_vendor_ids(uuid[])') is not null
  and pg_get_functiondef('public.get_dam_order_vendor_ids(uuid[])'::regprocedure) like '%cardinality(p_line_ids)>1500%'
  and not has_function_privilege('anon','public.get_dam_order_vendor_ids(uuid[])','execute')
  and has_function_privilege('authenticated','public.get_dam_order_vendor_ids(uuid[])','execute')
  and pg_get_functiondef('dam.orderlist_product_facts(uuid,text)'::regprocedure) like '%fallback_ambiguous%'
  and pg_get_functiondef('dam.orderlist_product_facts(uuid,text)'::regprocedure) like '%companyCode%'
  as passed;
