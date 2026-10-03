begin;

do $test$
declare
  v_tables integer;
  v_sequences integer;
  v_view text;
begin
  select count(*) into v_tables
  from information_schema.tables
  where table_schema = 'dflow_prod' and table_type = 'BASE TABLE';
  if v_tables <> 122 then
    raise exception 'expected 122 dflow_prod tables (103 + 19 Tracking tables, #2875), found %', v_tables;
  end if;

  select count(*) into v_sequences
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'dflow_prod'
    and c.relkind = 'S';
  if v_sequences <> 112 then
    raise exception 'expected 112 dflow_prod sequences (97 + 15 Tracking identities, #2875), found %', v_sequences;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'dflow_prod'
      and column_default like '%dflow.%'
  ) then
    raise exception 'dflow_prod default still references nonproduction dflow';
  end if;

  if to_regclass('dflow_archive."AuditLog"') is null
     or to_regclass('dflow_prod."AuditLogHistory"') is null then
    raise exception 'audit live/archive read contract is incomplete';
  end if;

  -- #2875 brought the current Tracking surface into dflow_prod; the retired
  -- names sample_visit/sample_visit_event were never part of it.
  if (select count(*) from information_schema.tables
      where table_schema = 'dflow_prod'
        and table_name in ('sample_import_job', 'sample_import_row', 'sample_movement',
                           'sample_shipment_line', 'sample_stop_closeout')) <> 5
     or not exists (select 1 from pg_class c where c.relnamespace = 'dflow_prod'::regnamespace
                    and c.relname = 'sample_visit_plan' and c.relkind = 'v')
     or to_regclass('dflow_prod.sample_visit') is not null
     or to_regclass('dflow_prod.sample_visit_event') is not null then
    raise exception 'dflow_prod Tracking surface does not match #2875';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'dflow_prod' and table_name = 'users'
      and column_name = 'office_location'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'dflow_prod' and table_name = 'users'
      and column_name = 'preferred_language'
  ) then
    raise exception 'current production user fields are missing';
  end if;

  select pg_get_viewdef('public.style_tracker_rows_with_bridge'::regclass, true)
    into v_view;
  if v_view not like '%dflow."RFQItem"%'
     or v_view not like '%dflow."RFQGroup"%'
     or v_view like '%dflow_prod."RFQItem"%'
     or v_view like '%dflow_prod."RFQGroup"%' then
    raise exception 'style tracker bridge moved before the guarded data cutover';
  end if;

  if (select count(*) from dflow_prod."AuditLog") <> 0
     or (select count(*) from dflow_archive."AuditLog") <> 0 then
    raise exception 'structure migration copied AuditLog rows';
  end if;
end
$test$;

rollback;
