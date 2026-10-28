-- shared-db#4909/#4941: Master Data auto-flow contracts. The live leg
-- (#4941): a plain INSERT into plm.item alone produces the linked Licensed
-- tracker row through trg_style_tracker_autoflow_on_item_insert — no explicit
-- function call. The scheduled leg (#4909) stays covered: dry-run reporting,
-- per-SKU dedupe across statements, pre-cutoff no-backfill, audit row_added,
-- cron backstop registration, and explicit-run idempotence.
-- LOCAL THROWAWAY DATABASE ONLY; never execute against production. Rolled back.
begin;

do $test$
declare
  v_cutoff timestamptz;
  v_old timestamptz := now() - interval '30 days';
  v_new timestamptz := now() + interval '1 day';
  v_result record;
  v_item_new uuid;
  v_row_id uuid;
  v_linked uuid;
  v_sku_new text := 'ZZTEST4941-NEW';
  v_sku_old text := 'ZZTEST4941-OLD';
  v_rows integer;
begin
  if has_function_privilege('authenticated', 'public.sync_new_items_into_style_tracker(boolean)', 'execute')
     or has_function_privilege('anon', 'public.sync_new_items_into_style_tracker(boolean)', 'execute') then
    raise exception 'sync_new_items_into_style_tracker must not be executable by anon/authenticated';
  end if;
  if has_function_privilege('anon', 'public.style_tracker_autoflow_on_item_insert()', 'execute')
     or has_function_privilege('authenticated', 'public.style_tracker_autoflow_on_item_insert()', 'execute') then
    raise exception 'trigger function must not be executable by anon/authenticated';
  end if;
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'plm.item'::regclass
                    and t.tgname = 'trg_style_tracker_autoflow_on_item_insert'
                    and not t.tgisinternal and t.tgenabled = 'O') then
    raise exception 'live trigger trg_style_tracker_autoflow_on_item_insert is missing or disabled';
  end if;

  -- Recover the shipped cutoff from the sync function body so fixtures straddle it.
  select (regexp_match(prosrc, 'v_cutoff[^:=]*:=[[:space:]]*''([^'']+)''', 'i'))[1]::timestamptz
    into v_cutoff from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'sync_new_items_into_style_tracker';
  if v_cutoff is null then
    raise exception 'could not read the cutoff constant from the function body';
  end if;
  v_old := least(v_old, v_cutoff - interval '1 day');
  v_new := greatest(v_new, v_cutoff + interval '1 day');

  -- LIVE PATH: a single post-cutoff item insert produces the row AND the link,
  -- with no explicit function call.
  insert into plm.item (item_number, source_system, source_id, raw, created_at)
  values (v_sku_new, 'zztest4941', 'new', '{}', v_new)
  returning id into v_item_new;

  select count(*) into v_rows from public.style_tracker_rows
   where sku = v_sku_new and tracker_type = 'licensed'
     and source_sheet = 'License.Style'
     and row_data ->> 'origin' = 'plm_item_autoflow';
  if v_rows <> 1 then
    raise exception 'live trigger must create exactly one licensed auto row on insert, found %', v_rows;
  end if;

  select b.plm_item_id into v_linked from plm.style_tracker_item_bridge b
   join public.style_tracker_rows r on r.id = b.style_tracker_row_id
   where r.sku = v_sku_new;
  if v_linked is distinct from v_item_new then
    raise exception 'live trigger must link the new row to its plm.item (% vs %)', v_item_new, v_linked;
  end if;

  -- LIVE dedupe across statements: a second item with the same normalized SKU
  -- must not create a second row.
  insert into plm.item (item_number, source_system, source_id, raw, created_at)
  values ('ZZTEST4941-MULTI', 'zztest4941', 'multia', '{}', v_new);
  insert into plm.item (item_number, source_system, source_id, raw, created_at)
  values (' zztest4941-multi ', 'zztest4941', 'multib', '{}', v_new);
  select count(*) into v_rows from public.style_tracker_rows
   where upper(btrim(sku)) = 'ZZTEST4941-MULTI';
  if v_rows <> 1 then
    raise exception 'duplicate-SKU second statement must not create a second row, found %', v_rows;
  end if;

  -- LIVE one-statement multi-row insert with distinct SKUs: one row each,
  -- proving the statement-level trigger sees the whole statement.
  insert into plm.item (item_number, source_system, source_id, raw, created_at)
  select 'ZZTEST4941-PAIR-'||g, 'zztest4941', 'pair'||g, '{}', v_new
   from generate_series(1,2) g;
  select count(*) into v_rows from public.style_tracker_rows
   where upper(btrim(sku)) in ('ZZTEST4941-PAIR-1','ZZTEST4941-PAIR-2');
  if v_rows <> 2 then
    raise exception 'statement with two distinct SKUs must yield two rows, found %', v_rows;
  end if;

  -- LIVE no-backfill: a pre-cutoff item insert must not create a row.
  insert into plm.item (item_number, source_system, source_id, raw, created_at)
  values (v_sku_old, 'zztest4941', 'old', '{}', v_old);
  select count(*) into v_rows from public.style_tracker_rows where sku = v_sku_old;
  if v_rows <> 0 then
    raise exception 'pre-cutoff item must not be backfilled by the live trigger';
  end if;

  -- Audit: the trigger-created row got its row_added entry.
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

  -- Scheduled path: with the trigger having handled every fixture, an explicit
  -- dry run reports zero eligible and an explicit real run inserts nothing.
  select * into v_result from public.sync_new_items_into_style_tracker(p_dry_run => true);
  if v_result.eligible_count is distinct from 0 then
    raise exception 'after the live trigger handled all fixtures, dry run must report 0 eligible: %', v_result;
  end if;
  select * into v_result from public.sync_new_items_into_style_tracker(p_dry_run => false);
  if v_result.inserted_count is distinct from 0 then
    raise exception 'explicit run must be a no-op after the live trigger: %', v_result;
  end if;
end
$test$;

rollback;
