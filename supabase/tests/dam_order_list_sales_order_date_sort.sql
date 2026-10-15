-- The SO Date sort key is exposed through the existing invoker-safe OrderList view.
do $$
declare helper pg_proc; find_fn pg_proc; view_options text[]; view_sql text;
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
  where oid='dam.orderlist_sales_order_received_date(uuid,text)'::regprocedure;
  if not helper.prosecdef or helper.provolatile <> 's' or not helper.proisstrict
     or helper.proconfig is distinct from array['search_path=pg_catalog'] then
    raise exception 'SO received date helper must remain strict, stable, and search-path pinned';
  end if;
  if has_function_privilege('anon',helper.oid,'execute')
     or exists(select 1 from aclexplode(helper.proacl) a where a.grantee=0 and a.privilege_type='EXECUTE')
     or not has_function_privilege('authenticated',helper.oid,'execute')
     or not has_function_privilege('service_role',helper.oid,'execute') then
    raise exception 'SO received date helper privileges differ from authenticated and service-role contract';
  end if;
  select pg_get_viewdef('api.dam_order_list'::regclass) into strict view_sql;
  if view_sql !~* 'dam\.orderlist_sales_order_received_date\s*\(\s*pol\.id\s*,\s*coldlion_ref\.source_id\s*\)'
     or position('coldlion_ref.is_primary' in view_sql)=0 then
    raise exception 'OrderList SO date must bind the helper to the primary source reference and exact line';
  end if;
  if helper.prosrc not ilike '%auth.uid() is not null%'
     or helper.prosrc not ilike '%auth.role() = ''service_role''%'
     or helper.prosrc not ilike '%source_ref.source_id=p_coldlion_source_id%' then
    raise exception 'SO date helper must require an authenticated caller and exact line-reference binding';
  end if;

  select * into strict find_fn from pg_proc
  where oid='public.find_dam_order_list_row(text,jsonb,jsonb)'::regprocedure;
  if find_fn.prosecdef or find_fn.provolatile <> 's'
     or find_fn.proconfig is distinct from array['search_path=pg_catalog, auth']
     or not has_function_privilege('authenticated',find_fn.oid,'execute')
     or has_function_privilege('anon',find_fn.oid,'execute')
     or has_function_privilege('service_role',find_fn.oid,'execute') then
    raise exception 'Find must retain authenticated invoker behavior';
  end if;
  if position('sales_order_received_date' in (select prosrc from pg_proc where oid=find_fn.oid))=0
     or position('sort_only_columns' in (select prosrc from pg_proc where oid=find_fn.oid))=0 then
    raise exception 'Find must keep SO Date sort-only';
  end if;
end $$;
