-- The SO Date sort key is exposed through the existing invoker-safe OrderList view.
do $$
declare helper pg_proc; find_fn pg_proc; view_options text[];
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='api' and table_name='dam_order_list'
      and column_name='sales_order_received_date' and data_type='date'
  ) then
    raise exception 'OrderList view is missing its SO received date sort key';
  end if;

  select c.reloptions into strict view_options
  from pg_class c where c.oid='api.dam_order_list'::regclass;
  if not ('security_invoker=true'=any(coalesce(view_options,'{}'::text[]))) then
    raise exception 'OrderList view must retain invoker security';
  end if;

  select * into strict helper from pg_proc
  where oid='dam.orderlist_sales_order_received_date(text)'::regprocedure;
  if not helper.prosecdef or helper.provolatile <> 's' or not helper.proisstrict
     or helper.proconfig is distinct from array['search_path=pg_catalog'] then
    raise exception 'SO received date helper must remain strict, stable, and search-path pinned';
  end if;
  if has_function_privilege('anon',helper.oid,'execute')
     or exists(select 1 from aclexplode(helper.proacl) a where a.grantee=0 and a.privilege_type='EXECUTE')
     or not has_function_privilege('authenticated',helper.oid,'execute') then
    raise exception 'SO received date helper privileges differ from authenticated-only contract';
  end if;

  select * into strict find_fn from pg_proc
  where oid='public.find_dam_order_list_row(text,jsonb,jsonb)'::regprocedure;
  if find_fn.prosecdef or not has_function_privilege('authenticated',find_fn.oid,'execute') then
    raise exception 'Find must retain authenticated invoker behavior';
  end if;
end $$;
