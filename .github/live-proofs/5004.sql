-- #5004 read-only live proof: the OrderList view carries the triage flag as
-- its last column and the guided resolver is callable by signed-in users.
select
  (select count(*) from pg_catalog.pg_attribute a
    where a.attrelid = 'api.dam_order_list'::regclass and a.attnum > 0 and not a.attisdropped) = 95
  and (select a.attname from pg_catalog.pg_attribute a
        where a.attrelid = 'api.dam_order_list'::regclass and a.attnum = 95) = 'coldlion_unmatched'
  and to_regprocedure('public.resolve_coldlion_triage(uuid,text,uuid)') is not null
  and has_function_privilege('authenticated', 'public.resolve_coldlion_triage(uuid,text,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.resolve_coldlion_triage(uuid,text,uuid)', 'execute')
  as live_proof_passed;
