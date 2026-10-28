-- shared-db#4909/#4941: Master Data auto-flow contracts. The live leg (#4941):
-- plm.import_item_master_data itself creates and links the Licensed tracker row
-- inside the same transaction as the item insert — one import call, no explicit
-- sync call. The scheduled leg (#4909) stays covered: dry-run reporting,
-- per-SKU dedupe across imports, pre-cutoff no-backfill, audit row_added, cron
-- backstop registration, and explicit-run idempotence.
-- LOCAL THROWAWAY DATABASE ONLY; never execute against production. Rolled back.
begin;

do $test$
declare
  v_cutoff timestamptz;
  v_result record;
  v_item_new uuid;
  v_row_id uuid;
  v_linked uuid;
  v_sku_new text := 'ZZ4941IMP-NEW';
  v_sku_old text := 'ZZ4941IMP-OLD';
  v_rows integer;
  v_new_time text;
  v_old_time text;
begin
  if has_function_privilege('authenticated', 'public.sync_new_items_into_style_tracker(boolean)', 'execute')
     or has_function_privilege('anon', 'public.sync_new_items_into_style_tracker(boolean)', 'execute') then
    raise exception 'sync_new_items_into_style_tracker must not be executable by anon/authenticated';
  end if;

  -- Recover the shipped cutoff from the sync function body so fixtures straddle it.
  select (regexp_match(prosrc, 'v_cutoff[^:=]*:=[[:space:]]*''([^'']+)''', 'i'))[1]::timestamptz
    into v_cutoff from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'sync_new_items_into_style_tracker';
  if v_cutoff is null then
    raise exception 'could not read the cutoff constant from the function body';
  end if;
  -- plm.item.created_at is set by the import (now()), so pre-cutoff coverage
  -- uses the explicit sync function with a manually inserted old row instead.
  v_new_time := to_char(greatest(now() + interval '1 day', v_cutoff + interval '1 day'), 'YYYY-MM-DD"T"HH24:MI:SS"Z"');

  -- LIVE PATH: one import call carrying a fresh item creates the item, the
  -- Licensed tracker row, AND the bridge link — no explicit sync call.
  select * into v_result from plm.import_item_master_data(jsonb_build_object(
    'sweepId', '0d38404e-0000-4000-8000-494100000001', 'terminalReached', true,
    'items', jsonb_build_array(jsonb_build_object(
      'companyCode', 'ZZ', 'divisionCode', 'ZZ', 'itemNo', v_sku_new,
      'description', 'zztest 4941 live import', 'createdTime', v_new_time))
  ));
  select id into v_item_new from plm.item where item_number = v_sku_new;
  if v_item_new is null then
    raise exception 'import did not create the item';
  end if;

  select count(*) into v_rows from public.style_tracker_rows
   where sku = v_sku_new and tracker_type = 'licensed'
     and source_sheet = 'License.Style'
     and row_data ->> 'origin' = 'plm_item_autoflow';
  if v_rows <> 1 then
    raise exception 'import must create exactly one licensed auto row for the new item, found %', v_rows;
  end if;

  select b.plm_item_id into v_linked from plm.style_tracker_item_bridge b
   join public.style_tracker_rows r on r.id = b.style_tracker_row_id
   where r.sku = v_sku_new;
  if v_linked is distinct from v_item_new then
    raise exception 'import must link the new row to its plm.item (% vs %)', v_item_new, v_linked;
  end if;

  -- LIVE dedupe: re-importing the same item (update path) must not create a
  -- second row.
  perform plm.import_item_master_data(jsonb_build_object(
    'sweepId', '0d38404e-0000-4000-8000-494100000002', 'terminalReached', true,
    'items', jsonb_build_array(jsonb_build_object(
      'companyCode', 'ZZ', 'divisionCode', 'ZZ', 'itemNo', v_sku_new,
      'description', 'zztest 4941 live import v2', 'createdTime', v_new_time))
  ));
  select count(*) into v_rows from public.style_tracker_rows
   where upper(btrim(sku)) = upper(btrim(v_sku_new));
  if v_rows <> 1 then
    raise exception 're-import must not duplicate the row, found %', v_rows;
  end if;

  -- Audit: the live-created row got its row_added entry.
  select r.id into v_row_id from public.style_tracker_rows r where r.sku = v_sku_new;
  if not exists (select 1 from public.style_tracker_audit_log a
                  where a.style_tracker_row_id = v_row_id and a.event_type = 'row_added') then
    raise exception 'row_added audit missing for the live-created row';
  end if;

  -- Cron backstop still registered.
  if not exists (select 1 from cron.job
                  where jobname = 'nightly-style-tracker-item-autoflow'
                    and schedule = '50 5 * * *'
                    and position('sync_new_items_into_style_tracker' in command) > 0) then
    raise exception 'cron backstop nightly-style-tracker-item-autoflow missing or misconfigured';
  end if;

  -- Scheduled path: after the live import handled the new item, an explicit
  -- dry run reports zero eligible and an explicit real run inserts nothing.
  select * into v_result from public.sync_new_items_into_style_tracker(p_dry_run => true);
  if v_result.eligible_count is distinct from 0 then
    raise exception 'after the live import, dry run must report 0 eligible: %', v_result;
  end if;
  select * into v_result from public.sync_new_items_into_style_tracker(p_dry_run => false);
  if v_result.inserted_count is distinct from 0 then
    raise exception 'explicit run must be a no-op after the live import: %', v_result;
  end if;

  -- Pre-cutoff no-backfill (explicit path; the import always creates post-cutoff
  -- rows): a manually inserted old item must not gain a row.
  insert into plm.item (item_number, source_system, source_id, raw, created_at)
  values (v_sku_old, 'zztest4941', 'old', '{}', least(now() - interval '30 days', v_cutoff - interval '1 day'));
  select count(*) into v_rows from public.style_tracker_rows where sku = v_sku_old;
  if v_rows <> 0 then
    raise exception 'pre-cutoff item must not be backfilled';
  end if;
end
$test$;

rollback;
