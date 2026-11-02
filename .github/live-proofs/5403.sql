-- Only the reader's source-protection and role contract; UI proof stays on #636.
select pg_get_functiondef('public.update_dam_order(uuid,jsonb,jsonb)'::regprocedure) like '%orderlist_source_correction%'
  and pg_get_functiondef('public.update_dam_order(uuid,jsonb,jsonb)'::regprocedure) like '%orderlist_google_correction%'
  and pg_get_functiondef('public.update_dam_order(uuid,jsonb,jsonb)'::regprocedure) like '%v_source_count<>1%'
  and pg_get_functiondef('public.update_dam_order(uuid,jsonb,jsonb)'::regprocedure) like '%v_actor is null%'
  as passed;
