-- The SO Date sort key is exposed through the existing invoker-safe OrderList view.
do $$
declare helper pg_proc; find_fn pg_proc; view_options text[]; view_sql text;
  allowed_filter_columns text; sort_only_columns text; plan_line text;
  plain_plan text := ''; count_plan text := '';
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
     or helper.prosrc not ilike '%source_ref.source_id=p_coldlion_source_id%'
     or helper.prosrc not ilike '%h.company_code = ''EDGEHOME''%'
     or helper.prosrc not ilike '%America/New_York%'
     or helper.prosrc not ilike '%count(*) = count(h.created_time)%'
     or helper.prosrc not ilike '%count(distinct h.created_time) = 1%'
     or helper.prosrc not ilike '%min(h.created_time) > timestamptz ''2000-01-01 00:00:00+00''%'
     or helper.prosrc not ilike '%^coldlion:so:%line:%component:%$%' then
    raise exception 'SO date helper must retain its access, source, company, timestamp, and New York date contract';
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
  select prosrc into strict view_sql from pg_proc where oid=find_fn.oid;
  allowed_filter_columns := split_part(split_part(view_sql,
    'allowed_columns constant text[] := array[',2),'];',1);
  sort_only_columns := split_part(split_part(view_sql,
    'sort_only_columns constant text[] := array[',2),'];',1);
  if position('sales_order_received_date' in allowed_filter_columns)>0
     or position('sales_order_received_date' in sort_only_columns)=0
     or view_sql not ilike '%d.%I %s nulls last%'
     or view_sql not ilike '%d.order_line_id asc nulls last%' then
    raise exception 'Find must keep SO Date sort-only with nulls-last sorting and stable line-ID ties';
  end if;
  for plan_line in execute
    'explain (costs off) select order_line_id, order_id, production_order_number, sku, order_date, quantity_ordered from api.dam_order_list'
  loop
    plain_plan := plain_plan || plan_line || E'\n';
  end loop;
  if plain_plan ilike '%orderlist_sales_order_received_date%' then
    raise exception 'An ordinary OrderList projection evaluates the SO-date helper: %',plain_plan;
  end if;
  for plan_line in execute 'explain (costs off) select count(*) from api.dam_order_list'
  loop
    count_plan := count_plan || plan_line || E'\n';
  end loop;
  if count_plan ilike '%orderlist_sales_order_received_date%' then
    raise exception 'An ordinary OrderList count evaluates the SO-date helper: %',count_plan;
  end if;
end $$;

-- Exercise the real view/helper/Find path against disposable rows in the CI database.
begin;
do $integration$
declare run_id uuid := gen_random_uuid(); order_id uuid := gen_random_uuid();
  row_ids uuid[] := array[
    gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];
  labels text[] := array['SO-SORT-A','SO-SORT-B','SO-SORT-C','SO-SORT-D'];
  source_ids text[] := array[
    'coldlion:so:910101:line:1:component:1',
    'coldlion:so:910102:line:1:component:1',
    'coldlion:so:910103:line:1:component:1',
    'coldlion:so:910104:line:1:component:1'];
  so_numbers bigint[] := array[910101,910102,910103,910104];
  stamps timestamptz[] := array[
    '2026-09-05 03:30:00+00'::timestamptz,
    '2026-09-05 03:30:00+00'::timestamptz,
    '2026-09-04 03:30:00+00'::timestamptz,
    null];
  expected_dates date[] := array[date '2026-09-04',date '2026-09-04',date '2026-09-03',null];
  i integer; found_date date; found_index bigint; expected_index bigint;
begin
  insert into coldlion.sync_run(id,endpoint,requested_by)
  values(run_id,'/orderlist-sort-test','database-contract-test');
  insert into plm.production_order(id,production_order_number,source_system,source_id)
  values(order_id,'SO-SORT-INTEGRATION','orderlist-sort-test',run_id::text);
  for i in 1..4 loop
    insert into plm.production_order_line(
      id,production_order_id,sku,metadata,source_system,source_id)
    values(row_ids[i],order_id,'ORDERLIST-SO-DATE-SORT-TEST',
      jsonb_build_object('order_list_snapshot',jsonb_build_object('description',labels[i])),
      'orderlist-sort-test',labels[i]);
    insert into plm.production_order_line_source_ref(
      production_order_line_id,source_system,source_id,is_primary)
    values(row_ids[i],'coldlion',source_ids[i],true);
    if stamps[i] is not null then
      insert into coldlion.order_history_line(
        company_code,sales_order_no,sales_order_line_no,master_item_no,
        line_source_hash,run_id,fetched_at,created_time)
      values('EDGEHOME',so_numbers[i],1,'SO-SORT-TEST-'||i,
        lpad(to_hex(i),64,'0'),run_id,now(),stamps[i]);
    end if;
  end loop;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
  if (select count(*) from api.dam_order_list
      where sku='ORDERLIST-SO-DATE-SORT-TEST') <> 4 then
    raise exception 'real OrderList view did not return all four integration rows';
  end if;
  for i in 1..4 loop
    select sales_order_received_date into found_date
      from api.dam_order_list where order_line_id=row_ids[i];
    if found_date is distinct from expected_dates[i] then
      raise exception 'real OrderList view SO-date integration failed for row %: got %, expected %',
        i,found_date,expected_dates[i];
    end if;
  end loop;
  for i in 1..4 loop
    select row_index into expected_index from (
      select order_line_id,
        row_number() over(order by sales_order_received_date desc nulls last,order_line_id)-1 row_index
      from api.dam_order_list where sku='ORDERLIST-SO-DATE-SORT-TEST'
    ) ranked where order_line_id=row_ids[i];
    select row_index into found_index
      from public.find_dam_order_list_row(labels[i],
        '[{"column":"sku","operator":"eq","value":"ORDERLIST-SO-DATE-SORT-TEST"}]'::jsonb,
        '[{"column":"sales_order_received_date","ascending":false}]'::jsonb);
    if found_index is distinct from expected_index then
      raise exception 'real Find SO-date ranking failed for row %: got index %',i,found_index;
    end if;
  end loop;
  for i in 1..4 loop
    select row_index into expected_index from (
      select order_line_id,
        row_number() over(order by sales_order_received_date asc nulls last,order_line_id)-1 row_index
      from api.dam_order_list where sku='ORDERLIST-SO-DATE-SORT-TEST'
    ) ranked where order_line_id=row_ids[i];
    select row_index into found_index
      from public.find_dam_order_list_row(labels[i],
        '[{"column":"sku","operator":"eq","value":"ORDERLIST-SO-DATE-SORT-TEST"}]'::jsonb,
        '[{"column":"sales_order_received_date","ascending":true}]'::jsonb);
    if found_index is distinct from expected_index then
      raise exception 'real Find SO-date ascending ranking failed for row %: got index %',i,found_index;
    end if;
  end loop;
end
$integration$;
rollback;
