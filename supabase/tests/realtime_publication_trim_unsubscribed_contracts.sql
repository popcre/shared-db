-- Contracts for 20261111162316_realtime_publication_trim_unsubscribed.sql
-- (u2giants/popdam3#804 task 1).
--
-- Where the supabase_realtime publication exists:
--   1. every table an application subscribes to is still published, so no live
--      update feature was removed;
--   2. the 13 tables with no listener are no longer published.
-- The publication is created by the Supabase platform, so a database without a
-- realtime stack is reported as an explicit skip in ephemeral CI only.
-- REQUIRED LIVE PROOF (not supplied by CI green): after preview apply and again
-- after automatic production promotion, run this file with ON_ERROR_STOP and
-- PGOPTIONS='-c shared_db.require_realtime_contract=on'. That mode rejects an
-- absent publication AND absent kept tables. Record both non-skip results on
-- issue #6056 before closing live proof; this offline change supplies neither.

begin;

do $contracts$
declare
  v_missing text;
  v_leftover text;
  v_strict boolean := coalesce(current_setting('shared_db.require_realtime_contract', true), 'off') = 'on';
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if v_strict then
      raise exception 'CONTRACT: supabase_realtime publication is required for live proof.';
    end if;
    raise notice 'SKIP: the supabase_realtime publication does not exist in this database, so membership cannot be asserted here.';
    return;
  end if;

  select string_agg(expected.name, ', ')
    into v_missing
  from unnest(array['public.admin_config','public.agent_registrations','public.style_tracker_rows','crm.email_message','crm.task','crm.note','crm.meeting_note','crm.opportunity','crm.department']::text[]) expected(name)
  where (v_strict or to_regclass(expected.name) is not null)
    and not exists (
      select 1 from pg_publication_tables p
       where p.pubname = 'supabase_realtime'
         and p.schemaname = split_part(expected.name, '.', 1)
         and p.tablename = split_part(expected.name, '.', 2));

  if v_missing is not null then
    raise exception 'CONTRACT: subscribed table(s) missing from supabase_realtime: %. An application listens to these with postgres_changes; removing them breaks a live update feature.', v_missing;
  end if;

  select string_agg(removed.name, ', ')
    into v_leftover
  from unnest(array['app.activity','app.comment','app.notification','crm.licensor_approval_thread','dam.asset','dam.style_group','pim.customer_order','pim.product','pim.product_assignee','pim.product_sample','pim.product_submission','pim.revision_request','pim.stage_history']::text[]) removed(name)
  where exists (
      select 1 from pg_publication_tables p
       where p.pubname = 'supabase_realtime'
         and p.schemaname = split_part(removed.name, '.', 1)
         and p.tablename = split_part(removed.name, '.', 2));

  if v_leftover is not null then
    raise exception 'CONTRACT: table(s) with no listener are still published by supabase_realtime: %. If a feature now subscribes to one, move it to the kept list in this contract in the same change that re-publishes it.', v_leftover;
  end if;

  raise notice 'OK: supabase_realtime publishes every subscribed table and none of the 13 trimmed tables.';
end;
$contracts$;

rollback;
