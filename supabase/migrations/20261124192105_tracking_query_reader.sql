-- popcre/designflow-tracking#138. Read-only role for query-plan inspection of
-- the Tracking production grid (page query and sales-order anchors).
-- derived-from: none
--
-- Owner request (Albert Hazan, 2026-11-24): "create the read-only login
-- yourself".
--
-- WHAT THIS CREATES: role tracking_query_reader — NOLOGIN here, SELECT only on
-- the exact relations the Tracking grid reads. No users/auth tables, no
-- functions, no writes. Login and password are enabled afterwards outside git;
-- the password lives only in 1Password vibe_coding (same pattern as
-- oracle_directory_reader, #5776).
--
-- Grants are guarded per relation: tables absent on a target (dflow_prod in
-- the from-empty replay) are skipped, never created.
--
-- statement_timeout 30s, idle_in_transaction_session_timeout 60s,
-- default_transaction_read_only on, connection limit 2.
--
-- PLAIN CREATE ROLE (no if-not-exists) on purpose: a pre-existing role with
-- unknown attributes must fail the apply rather than be adopted.
-- ROLLBACK (forward fix): drop owned by tracking_query_reader; drop role tracking_query_reader;

begin;
set lock_timeout = '5s';
set statement_timeout = '5min';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'tracking_query_reader') then
    raise exception 'ABORT tracking#138: role tracking_query_reader already exists; refusing to adopt it';
  end if;
end $$;

create role tracking_query_reader nologin noinherit nosuperuser nocreatedb nocreaterole noreplication connection limit 2;
comment on role tracking_query_reader is
  'designflow-tracking#138. Read-only query-plan login for the Tracking grid. SELECT on listed grid relations only.';
alter role tracking_query_reader set statement_timeout = '30s';
alter role tracking_query_reader set idle_in_transaction_session_timeout = '60s';
alter role tracking_query_reader set default_transaction_read_only = on;

do $$
declare
  rel text;
  sch text;
begin
  foreach rel in array array[
    'dflow_prod."ProdOrderHeader"',
    'dflow_prod."ProdOrderDetail"',
    'dflow_prod."itemHeader"',
    'dflow_prod.item_prod_order_detail_associations',
    'dflow_prod."licensingStatus"',
    'dflow_prod."merchGroup"',
    'dflow_prod."externalVendor"',
    'plm.v_prod_order_sales_order_link',
    'plm.prod_stage_progress',
    'plm.prod_stage_option',
    'plm.stage',
    'plm.stage_duration',
    'coldlion.order_history_line'
  ] loop
    if to_regclass(rel) is not null then
      sch := split_part(rel, '.', 1);
      execute format('grant usage on schema %I to tracking_query_reader', sch);
      execute format('grant select on %s to tracking_query_reader', rel);
    end if;
  end loop;
end $$;

commit;
