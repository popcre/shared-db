-- Structural proof; exact line and ordinary-user proof remain on PopDAM #638.
select to_regprocedure('public.get_dam_order_assortment_quantities(uuid[])') is not null
 and pg_get_functiondef('public.get_dam_order_assortment_quantities(uuid[])'::regprocedure) like '%coldlion_linked_from%'
 and pg_get_functiondef('public.get_dam_order_assortment_quantities(uuid[])'::regprocedure) like '%orderlist_source_correction%'
 and not has_function_privilege('anon','public.get_dam_order_assortment_quantities(uuid[])','execute')
 and has_function_privilege('authenticated','public.get_dam_order_assortment_quantities(uuid[])','execute') as passed;
