-- Issue #4909: Master Data auto-flow. Items born in DesignFlow reach plm.item through the
-- nightly ColdLion sweep (05:20 UTC, plm.import_item_master_data), but nothing created a
-- Master Data row for them: rows appeared only via the manual Add-row RPC or the Google
-- Sheet import, and plm.refresh_style_tracker_item_bridge only links rows that already
-- exist. This adds one additive function plus a nightly cron at 05:50 UTC (after the
-- sweep): for each plm.item born on/after the cutoff, insert one Licensed tracker row
-- (source_sheet 'License.Style', tracker_type 'licensed', sku =
-- coalesce(style_number, item_number), row_data {"origin":"plm_item_autoflow"}) and then
-- run the existing bridge refresh so the row arrives linked.
--
-- Deliberately incremental: items with created_at before the cutoff are NOT backfilled.
-- Idempotent: an item whose normalized SKU already has a tracker row (any tab) or whose
-- id is already bridged is skipped, so a re-run inserts nothing. No updates, no deletes,
-- cap 500 inserts per run with a warning for the remainder (nightly delta is 2-25/day).

begin;

create function public.sync_new_items_into_style_tracker(p_dry_run boolean default false)
returns table(eligible_count integer, inserted_count integer, deferred_count integer)
language plpgsql
security definer
set search_path = public, plm, pg_catalog
as $fn$
declare
  -- v_cutoff: 2026-10-28T00:00:00Z, the first nightly after promotion. Items first seen in the item
  -- master before this timestamp keep today's manual/add-row process by owner decision.
  v_cutoff timestamptz := '2026-10-28T00:00:00Z'::timestamptz;
  v_max_rows integer := 500;
  v_eligible integer;
  v_deferred integer;
  v_next_row_number integer;
begin
  select count(*) into v_eligible
  from plm.item i
  where i.created_at >= v_cutoff
    and coalesce(btrim(i.style_number), btrim(i.item_number)) <> ''
    and not exists (
      select 1 from public.style_tracker_rows r
      where upper(btrim(r.sku)) = upper(btrim(coalesce(i.style_number, i.item_number)))
    )
    and not exists (
      select 1 from plm.style_tracker_item_bridge b
      where b.plm_item_id = i.id
    );

  v_deferred := greatest(0, v_eligible - v_max_rows);
  if v_deferred > 0 then
    raise warning 'sync_new_items_into_style_tracker: % eligible items exceed the % row cap; % deferred to the next run',
      v_eligible, v_max_rows, v_deferred;
  end if;

  if p_dry_run then
    eligible_count := v_eligible;
    inserted_count := 0;
    deferred_count := v_deferred;
    return next;
    return;
  end if;

  select coalesce(max(source_row_number), 2) + 1 into v_next_row_number
  from public.style_tracker_rows
  where source_sheet = 'License.Style';

  with batch as (
    select i.id as plm_item_id,
           btrim(coalesce(i.style_number, i.item_number)) as sku_value,
           row_number() over (order by i.created_at, i.id) as rn
    from plm.item i
    where i.created_at >= v_cutoff
      and coalesce(btrim(i.style_number), btrim(i.item_number)) <> ''
      and not exists (
        select 1 from public.style_tracker_rows r
        where upper(btrim(r.sku)) = upper(btrim(coalesce(i.style_number, i.item_number)))
      )
      and not exists (
        select 1 from plm.style_tracker_item_bridge b
        where b.plm_item_id = i.id
      )
    limit v_max_rows
  )
  insert into public.style_tracker_rows (
    source_sheet, source_row_number, tracker_type, sku, row_data
  )
  select
    'License.Style',
    v_next_row_number + b.rn - 1,
    'licensed',
    b.sku_value,
    jsonb_build_object('origin', 'plm_item_autoflow')
  from batch b;

  get diagnostics inserted_count = row_count;

  -- Link the new rows through the existing, already-reviewed matcher: unique
  -- upper(trim(sku)) = upper(trim(coalesce(style_number, item_number))) wins, ambiguous
  -- SKUs stay unmatched for manual linking, exactly like hand-added rows.
  perform plm.refresh_style_tracker_item_bridge();

  eligible_count := v_eligible;
  deferred_count := v_deferred;
  return next;
end;
$fn$;

revoke all on function public.sync_new_items_into_style_tracker(boolean) from public, anon, authenticated;
grant execute on function public.sync_new_items_into_style_tracker(boolean) to service_role;

do $cron$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'nightly-style-tracker-item-autoflow'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'nightly-style-tracker-item-autoflow',
    '50 5 * * *',
    $cron_body$ select public.sync_new_items_into_style_tracker() $cron_body$
  );
end
$cron$;

commit;
