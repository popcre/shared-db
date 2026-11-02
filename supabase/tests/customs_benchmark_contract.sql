begin;
do $test$
declare t text;
begin
  foreach t in array array['customs_benchmark_dataset','customs_benchmark_artifact','customs_benchmark_observation'] loop
    if not exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='plm' and c.relname=t and c.relrowsecurity) then
      raise exception 'Missing private RLS table: %',t;
    end if;
    if has_table_privilege('anon','plm.'||t,'SELECT') or has_table_privilege('authenticated','plm.'||t,'SELECT') then
      raise exception 'Private customs table is browser-readable: %',t;
    end if;
    if not has_table_privilege('service_role','plm.'||t,'SELECT,INSERT') or has_table_privilege('service_role','plm.'||t,'DELETE') or has_table_privilege('service_role','plm.'||t,'UPDATE') then
      raise exception 'Archive privileges do not preserve append-only access: %',t;
    end if;
  end loop;
end $test$;
rollback;
