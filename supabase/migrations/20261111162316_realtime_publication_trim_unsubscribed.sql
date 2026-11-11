-- u2giants/popdam3#804 task 1: trim the supabase_realtime publication to the
-- tables an application actually listens to.
--
-- WHY
-- ---
-- Supabase Realtime polls realtime.list_changes continuously (production,
-- pg_stat_statements since 2026-11-06 11:20 AM EST: 995,771 calls, 39.1 ms mean,
-- ~7,760 s of database time per day). Every poll rebuilds the publication's
-- table list from pg_publication_tables, and that step costs catalog reads per
-- published table. A separate 7-table experiment measured 649 buffer hits
-- versus 1,251 with 22 tables. The audited target below keeps 9 tables; its
-- buffer cost has not been measured, so 649 is not a claim for this migration.
--
-- AUDIT (2026-11-11, default branches of every popcre and u2giants repository,
-- searched for `postgres_changes`, plus live realtime.subscription rows)
-- ---------------------------------------------------------------------------
-- Listened to, KEPT (9): public.admin_config, public.agent_registrations,
--   public.style_tracker_rows (PopDAM web and bridge agent); crm.email_message,
--   crm.task, crm.note, crm.meeting_note, crm.opportunity, crm.department
--   (PopCRM live refresh).
-- No listener in any repository, no live subscription, REMOVED (13): the tables
--   below. They were published by 20260621151155 and 20260621151419 ahead of
--   features that never subscribed. Re-publishing one later is a one-line
--   additive migration.
--
-- SCOPE
-- -----
-- Publication membership only. No table, policy, grant, index or replica
-- identity changes. Each statement is guarded so a database with no realtime
-- stack is a clean no-op. Existing kept tables are added if unpublished;
-- missing tables are left for the strict live contract to report.
begin;
set local lock_timeout='2s';
set local statement_timeout='60s';
set local search_path=pg_catalog;

do $trim$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'supabase_realtime publication absent; nothing to trim.';
    return;
  end if;

  -- Converge the audited kept set even when platform setup never published it.
  if to_regclass('public.admin_config') is not null and not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'admin_config'
  ) then
    alter publication supabase_realtime add table public.admin_config;
  end if;

  if to_regclass('public.agent_registrations') is not null and not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'agent_registrations'
  ) then
    alter publication supabase_realtime add table public.agent_registrations;
  end if;

  if to_regclass('public.style_tracker_rows') is not null and not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'style_tracker_rows'
  ) then
    alter publication supabase_realtime add table public.style_tracker_rows;
  end if;

  if to_regclass('crm.email_message') is not null and not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'crm' and tablename = 'email_message'
  ) then
    alter publication supabase_realtime add table crm.email_message;
  end if;

  if to_regclass('crm.task') is not null and not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'crm' and tablename = 'task'
  ) then
    alter publication supabase_realtime add table crm.task;
  end if;

  if to_regclass('crm.note') is not null and not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'crm' and tablename = 'note'
  ) then
    alter publication supabase_realtime add table crm.note;
  end if;

  if to_regclass('crm.meeting_note') is not null and not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'crm' and tablename = 'meeting_note'
  ) then
    alter publication supabase_realtime add table crm.meeting_note;
  end if;

  if to_regclass('crm.opportunity') is not null and not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'crm' and tablename = 'opportunity'
  ) then
    alter publication supabase_realtime add table crm.opportunity;
  end if;

  if to_regclass('crm.department') is not null and not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'crm' and tablename = 'department'
  ) then
    alter publication supabase_realtime add table crm.department;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'app' and tablename = 'activity') then
    alter publication supabase_realtime drop table app.activity;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'app' and tablename = 'comment') then
    alter publication supabase_realtime drop table app.comment;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'app' and tablename = 'notification') then
    alter publication supabase_realtime drop table app.notification;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'crm' and tablename = 'licensor_approval_thread') then
    alter publication supabase_realtime drop table crm.licensor_approval_thread;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'dam' and tablename = 'asset') then
    alter publication supabase_realtime drop table dam.asset;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'dam' and tablename = 'style_group') then
    alter publication supabase_realtime drop table dam.style_group;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'pim' and tablename = 'customer_order') then
    alter publication supabase_realtime drop table pim.customer_order;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'pim' and tablename = 'product') then
    alter publication supabase_realtime drop table pim.product;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'pim' and tablename = 'product_assignee') then
    alter publication supabase_realtime drop table pim.product_assignee;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'pim' and tablename = 'product_sample') then
    alter publication supabase_realtime drop table pim.product_sample;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'pim' and tablename = 'product_submission') then
    alter publication supabase_realtime drop table pim.product_submission;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'pim' and tablename = 'revision_request') then
    alter publication supabase_realtime drop table pim.revision_request;
  end if;

  if exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'pim' and tablename = 'stage_history') then
    alter publication supabase_realtime drop table pim.stage_history;
  end if;
end;
$trim$;

commit;
