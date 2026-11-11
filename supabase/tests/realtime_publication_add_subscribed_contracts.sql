-- Contracts for 20261111221929_realtime_publication_add_subscribed.sql
-- (u2giants/popdam3#804 task 2).
--
-- Where the supabase_realtime publication exists, every table an application
-- subscribes to (and that exists in this database) is published. The
-- publication is created by the Supabase platform, so a database without a
-- realtime stack is reported as an explicit skip.

begin;

do $contracts$
declare
  v_missing text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'SKIP: the supabase_realtime publication does not exist in this database, so membership cannot be asserted here.';
    return;
  end if;

  select string_agg(expected.name, ', ')
    into v_missing
  from unnest(array['public.render_queue','crm.ingested_domain','core.contact','core.contact_company','public.admin_config','public.agent_registrations']::text[]) expected(name)
  where to_regclass(expected.name) is not null
    and not exists (
      select 1 from pg_publication_tables p
       where p.pubname = 'supabase_realtime'
         and p.schemaname = split_part(expected.name, '.', 1)
         and p.tablename = split_part(expected.name, '.', 2));

  if v_missing is not null then
    raise exception 'CONTRACT: subscribed table(s) missing from supabase_realtime: %. An application listens to these with postgres_changes.', v_missing;
  end if;

  raise notice 'OK: supabase_realtime publishes every table added by 20261111221929.';
end;
$contracts$;

rollback;
