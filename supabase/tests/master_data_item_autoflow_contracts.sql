-- shared-db#4909: public.sync_new_items_into_style_tracker creates exactly one Licensed
-- tracker row per new plm.item born after the cutoff, skips SKUs that already have a row
-- and items already bridged, is idempotent, honors the dry-run flag, and is not callable
-- by anon/authenticated. LOCAL THROWAWAY DATABASE ONLY; never execute against production.
-- Rolled back.
begin;

-- The shipped function cutoff is a fixed timestamp in the future at authoring time; the
-- tests below must exercise both sides of it, so they drive the real cutoff by fixture
-- dates chosen around it at run time (cutoff is read from the function body constant).
do $test$
declare
  v_cutoff timestamptz;
  v_old timestamptz := now() - interval '30 days';
  v_new timestamptz := now() + interval '1 day';
  v_result record;
  v_item_old uuid;
  v_item_new uuid;
  v_item_new2 uuid;
  v_sku_new text := 'ZZTEST4909-NEW';
  v_sku_old text := 'ZZTEST4909-OLD';
  v_rows integer;
begin
  if has_function_privilege('authenticated', 'public.sync_new_items_into_style_tracker(boolean)', 'execute')
     or has_function_privilege('anon', 'public.sync_new_items_into_style_tracker(boolean)', 'execute') then
    raise exception 'sync_new_items_into_style_tracker must not be executable by anon/authenticated';
  end if;
  if not has_function_privilege('service_role', 'public.sync_new_items_into_style_tracker(boolean)', 'execute') then
    raise exception 'service_role must execute sync_new_items_into_style_tracker';
  end if;

  -- Recover the shipped cutoff from the function body so the fixtures straddle it.
  select (regexp_match(prosrc, 'v_cutoff[^:=]*:=[[:space:]]*''([^'']+)''', 'i'))[1]::timestamptz
    into v_cutoff from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'sync_new_items_into_style_tracker';
  if v_cutoff is null then
    raise exception 'could not read the cutoff constant from the function body';
  end if;
  v_old := least(v_old, v_cutoff - interval '1 day');
  v_new := greatest(v_new, v_cutoff + interval '1 day');

  -- Fixture: one item born before the cutoff (must NOT flow in), one born after with a
  -- fresh SKU (must flow in), one born after whose SKU already has a tracker row (must
  -- be skipped), and one born after that is already bridged (must be skipped).
  insert into plm.item (item_number, source_system, source_id, raw, created_at)
  values (v_sku_old, 'zztest4909', 'old', '{}', v_old)
  returning id into v_item_old;
  insert into plm.item (item_number, source_system, source_id, raw, created_at)
  values (v_sku_new, 'zztest4909', 'new', '{}', v_new)
  returning id into v_item_new;
  insert into plm.item (item_number, source_system, source_id, raw, created_at)
  values ('ZZTEST4909-DUP', 'zztest4909', 'dup', '{}', v_new)
  returning id into v_item_new2;
  insert into plm.item (item_number, source_system, source_id, raw, created_at)
  values ('ZZTEST4909-BRIDGED', 'zztest4909', 'bridged', '{}', v_new);

  insert into public.style_tracker_rows (source_sheet, source_row_number, tracker_type, sku, row_data)
  values ('License.Style', 9900001, 'licensed', 'zztest4909-dup', '{}');

  -- Bridge fixture on its own tracker row.
  insert into public.style_tracker_rows (source_sheet, source_row_number, tracker_type, sku, row_data)
  values ('License.Style', 9900002, 'licensed', 'ZZTEST4909-BRIDGED', '{}');
  insert into plm.style_tracker_item_bridge (
    style_tracker_row_id, source_workbook_id, source_sheet, tracker_type, plm_item_id
  )
  select r.id, r.source_workbook_id, r.source_sheet, r.tracker_type, i.id
  from public.style_tracker_rows r, plm.item i
  where r.sku = 'ZZTEST4909-BRIDGED' and i.item_number = 'ZZTEST4909-BRIDGED';

  -- Dry run reports eligibility but writes nothing.
  select * into v_result from public.sync_new_items_into_style_tracker(p_dry_run => true);
  if v_result.inserted_count <> 0 then
    raise exception 'dry run must not insert rows: %', v_result;
  end if;
  select count(*) into v_rows from public.style_tracker_rows where sku = v_sku_new;
  if v_rows <> 0 then raise exception 'dry run wrote a row'; end if;
  if v_result.eligible_count is distinct from 1 then
    raise exception 'expected exactly 1 eligible item (pre-cutoff, dup-sku and bridged skipped): %', v_result;
  end if;

  -- Real run inserts exactly the new item, as licensed, with the origin marker.
  select * into v_result from public.sync_new_items_into_style_tracker(p_dry_run => false);
  if v_result.inserted_count is distinct from 1 then
    raise exception 'expected exactly 1 inserted row: %', v_result;
  end if;
  select count(*) into v_rows from public.style_tracker_rows
   where sku = v_sku_new and tracker_type = 'licensed'
     and source_sheet = 'License.Style'
     and row_data ->> 'origin' = 'plm_item_autoflow';
  if v_rows <> 1 then raise exception 'auto row missing or malformed'; end if;

  -- Pre-cutoff item never flowed in.
  select count(*) into v_rows from public.style_tracker_rows where sku = v_sku_old;
  if v_rows <> 0 then raise exception 'pre-cutoff item must not be backfilled'; end if;

  -- Idempotent: an immediate re-run finds nothing eligible.
  select * into v_result from public.sync_new_items_into_style_tracker(p_dry_run => true);
  if v_result.eligible_count is distinct from 0 then
    raise exception 're-run must be idempotent: %', v_result;
  end if;
end
$test$;

rollback;
