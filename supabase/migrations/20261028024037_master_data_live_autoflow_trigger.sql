-- Issue #4941: Master Data live auto-flow. #4909/PR #4912 shipped the nightly
-- create+link job (cron nightly-style-tracker-item-autoflow). Owner direction
-- 2026-10-27: "i want it to be live, not done like a cron job. the whole idea of
-- sharing the same database is that we don't have to schedule events to sync
-- data." This adds the live leg: a statement-level AFTER INSERT trigger on
-- plm.item runs the existing public.sync_new_items_into_style_tracker() inside
-- the inserting transaction, so the Licensed Master Data row exists and is
-- linked the moment an item enters the shared database. Together with the
-- 30-minute item-feed schedule change in this same PR, a DesignFlow item born
-- during business hours appears in Master Data within one feed cycle.
--
-- The nightly 05:50 UTC cron stays as an idempotent backstop (a zero-insert
-- run costs one count query; the function skips the bridge refresh when it
-- inserted nothing). The sync function body is unchanged: same cutoff, dedupe,
-- cap and linking semantics; the trigger only changes WHEN it runs.

begin;

create function public.style_tracker_autoflow_on_item_insert()
returns trigger
language plpgsql
security definer
set search_path = public, plm, pg_catalog
as $fn$
begin
  -- One call per INSERT statement on plm.item. Bulk loads of pre-cutoff items
  -- are protected by the function's fixed cutoff; a statement inserting more
  -- than the per-run cap defers the remainder to the nightly backstop. This
  -- function writes style_tracker_rows and the bridge only, never plm.item, so
  -- it cannot recurse.
  perform * from public.sync_new_items_into_style_tracker(p_dry_run => false);
  return null;
end;
$fn$;

revoke all on function public.style_tracker_autoflow_on_item_insert() from public, anon, authenticated;

comment on function public.style_tracker_autoflow_on_item_insert() is
  'Live Master Data auto-flow (#4941): runs the idempotent item->style-tracker sync inside the inserting transaction. Not directly callable; attached to trg_style_tracker_autoflow_on_item_insert on plm.item.';

create trigger trg_style_tracker_autoflow_on_item_insert
  after insert on plm.item
  for each statement
  execute function public.style_tracker_autoflow_on_item_insert();

do $verify$
declare
  v_fn record;
  v_trg record;
begin
  select prosecdef, proconfig into v_fn from pg_proc
   where oid = 'public.style_tracker_autoflow_on_item_insert()'::regprocedure;
  if not v_fn.prosecdef
     or v_fn.proconfig is distinct from array['search_path=public, plm, pg_catalog'] then
    raise exception '#4941: trigger function lost SECURITY DEFINER or search_path';
  end if;
  if has_function_privilege('anon', 'public.style_tracker_autoflow_on_item_insert()', 'execute')
     or has_function_privilege('authenticated', 'public.style_tracker_autoflow_on_item_insert()', 'execute') then
    raise exception '#4941: trigger function must not be executable by anon/authenticated';
  end if;

  select t.tgenabled, t.tgtype into v_trg from pg_trigger t
   where t.tgrelid = 'plm.item'::regclass
     and t.tgname = 'trg_style_tracker_autoflow_on_item_insert' and not t.tgisinternal;
  -- tgtype bits: ROW=1, BEFORE=2, INSERT=4. AFTER is the default (no bit).
  -- Statement-level AFTER INSERT = 4 exactly.
  if v_trg.tgenabled is distinct from 'O' or v_trg.tgtype is distinct from 4 then
    raise exception '#4941: trigger missing, disabled, or not statement-level AFTER INSERT';
  end if;

  if to_regprocedure('public.sync_new_items_into_style_tracker(boolean)') is null then
    raise exception '#4941: public.sync_new_items_into_style_tracker(boolean) is missing';
  end if;
end
$verify$;

commit;
