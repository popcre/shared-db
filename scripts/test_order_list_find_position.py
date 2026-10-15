"""Synthetic SQL behavior/RLS tests in a uniquely created loopback database.

Set TEST_DATABASE_URL to a local maintenance database with CREATE DATABASE rights.
No shared Supabase access is accepted. Existing cluster roles are never altered.
"""
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import urlsplit, urlunsplit
import uuid

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/migrations/20261015201243_orderlist_so_date_sort.sql'


def main():
    url = os.environ.get('TEST_DATABASE_URL', '')
    parsed = urlsplit(url)
    if parsed.scheme not in ('postgres', 'postgresql') or parsed.hostname not in ('127.0.0.1', 'localhost', '::1'):
        raise SystemExit('TEST_DATABASE_URL must name a disposable loopback PostgreSQL maintenance database')
    name = 'order_find_test_' + uuid.uuid4().hex
    test_url = urlunsplit(parsed._replace(path='/' + name))

    def run(dsn, sql):
        result = subprocess.run(['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', dsn], input=sql,
                                capture_output=True, text=True, timeout=90)
        if result.returncode:
            raise RuntimeError(result.stderr)

    full_migration = MIGRATION.read_text()
    helper_start = full_migration.index('create or replace function dam.orderlist_sales_order_received_date(')
    helper_end = full_migration.index('\n\ncreate or replace view api.dam_order_list', helper_start)
    helper_migration = full_migration[helper_start:helper_end]
    find_start = full_migration.index('create or replace function public.find_dam_order_list_row(')
    find_end = full_migration.index('\n\ncommit;', find_start)
    migration = full_migration[find_start:find_end]
    allowed_columns = migration.split('allowed_columns constant text[] := array[')[1].split('];')[0]
    sort_only_columns = migration.split('sort_only_columns constant text[] := array[')[1].split('];')[0]
    columns = list(dict.fromkeys(re.findall(r"'([a-z_]+)'", allowed_columns + sort_only_columns)))
    dates = {c for c in columns if c.endswith('_date')} | {'etd', 'eta'}
    numbers = {'quantity_ordered', 'quantity_shipped', 'unit_cost', 'order_depth_inches', 'cases_reported', 'case_pack', 'assortment_component_ordinal'}
    booleans = {'close_tracking', 'contractual_sample_reorder'}
    definitions = ','.join('"' + c + '" ' + ('uuid primary key' if c == 'order_line_id' else 'date' if c in dates else 'numeric' if c in numbers else 'boolean' if c in booleans else 'text') for c in columns)
    fixture = f"""
create schema auth; create schema api; create schema plm; create schema coldlion; create schema dam;
create function auth.uid() returns uuid language sql stable as 'select nullif(current_setting(''request.jwt.claim.sub'',true),'''')::uuid';
create function auth.role() returns text language sql stable as 'select current_setting(''request.jwt.claim.role'',true)';
grant usage on schema auth,api,dam to authenticated,service_role;
create table plm.production_order_line(id uuid primary key);
create table plm.production_order_line_source_ref(production_order_line_id uuid,source_system text,source_id text,is_primary boolean);
create table coldlion.order_history_line(company_code text,sales_order_no bigint,created_time timestamptz);
grant usage on schema plm,coldlion to authenticated,service_role;
grant select on plm.production_order_line,plm.production_order_line_source_ref,coldlion.order_history_line to authenticated,service_role;
insert into plm.production_order_line values
 ('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002'),
 ('10000000-0000-0000-0000-000000000003'),('10000000-0000-0000-0000-000000000004'),
 ('10000000-0000-0000-0000-000000000005');
insert into plm.production_order_line_source_ref values
 ('10000000-0000-0000-0000-000000000001','coldlion','coldlion:so:910001:line:1:component:1',true),
 ('10000000-0000-0000-0000-000000000002','coldlion','coldlion:so:910002:line:1:component:1',true),
 ('10000000-0000-0000-0000-000000000003','coldlion','coldlion:so:910003:line:1:component:1',true),
 ('10000000-0000-0000-0000-000000000004','coldlion','coldlion:so:910004:line:1:component:1',true),
 ('10000000-0000-0000-0000-000000000005','coldlion','coldlion:so:910005:line:1:component:1',true);
insert into coldlion.order_history_line values
 ('EDGEHOME',910001,'2026-09-05 03:30:00+00'),('EDGEHOME',910001,'2026-09-05 03:30:00+00'),
 ('EDGEHOME',910002,'2026-09-05 03:30:00+00'),('EDGEHOME',910002,'2026-09-05 04:30:00+00'),
 ('EDGEHOME',910003,null),('OTHER',910004,'2026-09-05 03:30:00+00');
create table public.find_fixture(owner_id uuid not null, {definitions});
alter table public.find_fixture enable row level security;
create policy owner_rows on public.find_fixture for select to authenticated using(owner_id=auth.uid());
grant select on public.find_fixture to authenticated;
create view api.dam_order_list with (security_invoker=true) as select {','.join('"'+c+'"' for c in columns)} from public.find_fixture;
grant select on api.dam_order_list to authenticated;
insert into public.find_fixture(owner_id,order_line_id,order_date,sales_order_received_date,sku,quantity_ordered,customer_name,vendor_name,snapshot_description)
values
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','00000000-0000-0000-0000-000000000001','2026-09-03','2026-09-05','ALPHA',20,'North','V1','plain'),
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','00000000-0000-0000-0000-000000000002','2026-09-02','2026-09-03','TARGET',10,'North','V2','literal 100% _ '||chr(92)),
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','00000000-0000-0000-0000-000000000003','2026-09-02','2026-09-03','target second',30,'South',null,'other'),
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','00000000-0000-0000-0000-000000000004',null,null,'ZETA',null,null,'V4',null),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','00000000-0000-0000-0000-000000000005','2026-09-04','2026-09-04','TARGET hidden',1,'North','hidden','hidden');
"""
    checks = r"""
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',false);
do $test$
declare r record; count_tests integer := 0; c record; expected uuid; expected_index bigint;
begin
  for c in select * from (values
    ('target','[]','[]',2,1),
    ('target','[]','[{"column":"quantity_ordered","ascending":false}]',3,0),
    ('target','[{"column":"customer_name","operator":"eq","value":"North"}]','[]',2,1),
    ('target','[{"column":"quantity_ordered","operator":"gte","value":25}]','[]',3,0),
    ('target','[{"column":"order_date","operator":"lte","value":"2026-09-02"}]','[]',2,0),
    ('target','[{"column":"vendor_name","operator":"is","value":null}]','[]',3,0),
    ('target','[{"column":"vendor_name","operator":"not.is","value":null}]','[]',2,1),
    ('target','[{"column":"sku","operator":"ilike","value":"target%"}]','[]',2,0),
    ('target','[{"column":"sku","operator":"not.ilike","value":"%second%"}]','[]',2,1),
    ('target','[{"column":"quantity_ordered","operator":"gt","value":10},{"column":"quantity_ordered","operator":"lt","value":31}]','[]',3,1),
    ('target','[{"column":"quantity_ordered","operator":"neq","value":20}]','[]',2,0),
    ('target','[]','[{"column":"order_date","ascending":true}]',2,0),
    ('target','[]','[{"column":"sales_order_received_date","ascending":false}]',2,1),
    ('target','[]','[{"column":"sales_order_received_date","ascending":true}]',2,0),
    ('ZETA','[]','[{"column":"sales_order_received_date","ascending":true}]',4,3),
    ('ZETA','[]','[{"column":"sales_order_received_date","ascending":false}]',4,3),
    ('%','[]','[]',2,1),
    ('_','[]','[]',2,1)
  ) as cases(search,filters,sort,id,idx) loop
    select * into r from public.find_dam_order_list_row(c.search,c.filters::jsonb,c.sort::jsonb);
    expected := ('00000000-0000-0000-0000-'||lpad(c.id::text,12,'0'))::uuid;
    if r.order_line_id is distinct from expected or r.row_index is distinct from c.idx::bigint then
      raise exception 'behavior case % failed', count_tests+1;
    end if;
    count_tests := count_tests+1;
  end loop;
  if (select row_index from public.find_dam_order_list_row(chr(92))) is distinct from 1::bigint then raise exception 'literal slash failed'; end if;
  if (select row_index from public.find_dam_order_list_row(chr(9)||'TARGET'||chr(160))) is distinct from 1::bigint then raise exception 'JS whitespace trim parity failed'; end if;
  if exists(select from public.find_dam_order_list_row(' ')) or exists(select from public.find_dam_order_list_row('no match'))
    or exists(select from public.find_dam_order_list_row(null)) or exists(select from public.find_dam_order_list_row('hidden')) then
    raise exception 'empty/no-match/RLS search failed';
  end if;
  -- Compare independently numbered unsearched view with every visible row's
  -- unique search term, under both directions and stable null-last ties.
  for c in select * from (values ('ALPHA'),('TARGET'),('second'),('ZETA')) t(term) loop
    select order_line_id,idx into expected,expected_index from (
      select d.*,row_number() over(order by order_date desc nulls last,order_line_id)-1 idx
      from api.dam_order_list d) ranked where sku ilike '%'||c.term||'%' order by idx limit 1;
    select * into r from public.find_dam_order_list_row(c.term);
    if r.order_line_id is distinct from expected or r.row_index is distinct from expected_index then raise exception 'independent ranking parity failed'; end if;
  end loop;
  for c in select * from (values
    ('[{"column":"sku; drop table public.find_fixture;--","operator":"eq","value":"x"}]','[]'),
    ('[{"column":"sku","operator":"eq) or true--","value":"x"}]','[]'),
    ('[]','[{"column":"sku","ascending":"desc;select 1"}]'),
    ('[{"column":"sales_order_received_date","operator":"eq","value":"2026-09-03"}]','[]'),
    ('{}','[]'), ('[null]','[]'),
    ('[{"column":"sku","operator":"eq","value":{}}]','[]'),
    ('[{"column":"sku","operator":"is","value":"null"}]','[]')
  ) t(filters,sort) loop
    begin
      perform * from public.find_dam_order_list_row('target',c.filters::jsonb,c.sort::jsonb);
      raise exception 'invalid input was accepted';
    exception when invalid_parameter_value then null; end;
  end loop;
  if exists(select from public.find_dam_order_list_row('target','[{"column":"sku","operator":"eq","value":"x'' OR true --"}]')) then raise exception 'literal injection matched'; end if;
  perform set_config('request.jwt.claim.sub','',false);
  begin
    perform * from public.find_dam_order_list_row('target'); raise exception 'missing identity accepted';
  exception when insufficient_privilege then null; end;
end $test$;
reset role;
set role anon;
do $$ begin
  begin perform * from public.find_dam_order_list_row('target'); raise exception 'anon accepted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
"""
    created = False
    try:
        run(url, f'CREATE DATABASE "{name}";')
        created = True
        run(test_url, fixture + helper_migration + migration + (ROOT/'supabase/tests/dam_order_list_find_position.sql').read_text() + checks + r'''
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',false);
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',false);
do $so_date$
begin
  if dam.orderlist_sales_order_received_date('10000000-0000-0000-0000-000000000001','coldlion:so:910001:line:1:component:1') is distinct from date '2026-09-04' then raise exception 'New York date conversion or repeated identical timestamps failed'; end if;
  if dam.orderlist_sales_order_received_date('10000000-0000-0000-0000-000000000002','coldlion:so:910002:line:1:component:1') is not null then raise exception 'conflicting history timestamps must be blank'; end if;
  if dam.orderlist_sales_order_received_date('10000000-0000-0000-0000-000000000003','coldlion:so:910003:line:1:component:1') is not null
     or dam.orderlist_sales_order_received_date('10000000-0000-0000-0000-000000000004','coldlion:so:910004:line:1:component:1') is not null
     or dam.orderlist_sales_order_received_date('10000000-0000-0000-0000-000000000005','coldlion:so:910005:line:1:component:1') is not null then raise exception 'null, wrong-company, or missing history must be blank'; end if;
  if dam.orderlist_sales_order_received_date('10000000-0000-0000-0000-000000000005','coldlion:so:910001:line:1:component:1') is not null then raise exception 'source ID was not bound to its exact order line'; end if;
  perform set_config('request.jwt.claim.sub','',false);
  if dam.orderlist_sales_order_received_date('10000000-0000-0000-0000-000000000001','coldlion:so:910001:line:1:component:1') is not null then raise exception 'unauthenticated helper call returned a date'; end if;
end $so_date$;
reset role;
set role service_role;
select set_config('request.jwt.claim.role','service_role',false);
do $service_role$
begin
  if dam.orderlist_sales_order_received_date('10000000-0000-0000-0000-000000000001','coldlion:so:910001:line:1:component:1') is distinct from date '2026-09-04' then raise exception 'service_role helper execution failed'; end if;
end $service_role$;
reset role;
''')
        print('OrderList Find: 18 position cases, 4 ranking parity cases, and live helper checks for New York dates, duplicate/conflicting/missing history, company scope, exact-line binding, authentication, and service_role passed; 0 skipped.')
    finally:
        if created:
            run(url, f'DROP DATABASE "{name}";')


if __name__ == '__main__':
    main()
