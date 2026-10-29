-- Master Data auto-flow: file generic-division items in the Generic list.
-- Owner direction 2026-10-29: "there is 1 generic division and 2 licensed
-- divisions. check the division." EH001 is generic; CW001 and SP001 are
-- licensed. Until now sync_new_items_into_style_tracker filed every new item as
-- Licensed (e.g. AA066ANBAT01, an EH001 item). Body is otherwise identical to
-- 20261028183729; only the sheet, row number and tracker_type now follow the
-- division.

create or replace function public.sync_new_items_into_style_tracker(p_dry_run boolean default false, p_cutoff timestamptz default '2026-10-28T00:00:00Z'::timestamptz)
returns table(eligible_count integer, inserted_count integer, deferred_count integer)
language plpgsql
security definer
set search_path = public, plm, pg_catalog
as $fn$
declare
  -- p_cutoff: 2026-10-28T00:00:00Z, the first nightly after promotion. Items first seen
  -- in the item master before this timestamp keep today's manual/add-row process by
  -- owner decision (#4909). #4974 exposes it as a parameter for the one-time
  -- pre-cutoff sweep only; the default is unchanged and the cron backstop uses it.
  v_max_rows integer := 500;
  v_eligible integer;
  v_deferred integer;
  v_next_row_number integer;
  v_next_generic_row_number integer;
  v_masters_fetched_at timestamptz;
begin
  -- Assortment evidence clock (#4956, hardened #4974 review round 1 H2): only a
  -- FULL masters projection ('coldlion-landing sync-masters', which pulls every
  -- item's details) may clear a rowless item. The item-sweep delta lands rows too
  -- but is per-item and partial — its runs must not advance this clock, or a
  -- transiently-failed assortment pull would be wrongly cleared by the next delta
  -- landing some other item.
  select max(finished_at) into v_masters_fetched_at
    from coldlion.sync_run
   where endpoint = '/itemDetails'
     and requested_by = 'coldlion-landing sync-masters'
     and status = 'succeeded';

  -- One candidate per normalized SKU: DISTINCT ON picks the oldest plm.item, so two new
  -- plm.item rows sharing upper(btrim(sku)) in one run cannot insert two tracker rows.
  with deduped as (
    select distinct on (upper(btrim(coalesce(i.style_number, i.item_number))))
           i.id as plm_item_id,
           btrim(coalesce(i.style_number, i.item_number)) as sku_value,
           i.created_at,
           coalesce(nullif(i.raw ->> 'itemDisplayDesc', ''), nullif(i.raw ->> 'itemDesc', ''), nullif(i.description, '')) as desc_value,
           lic.name as licensor_value,
           case lower(btrim(i.raw ->> 'itemDiscontinued'))
             when 'y' then true when 'true' then true when 't' then true when '1' then true
             when 'n' then false when 'false' then false when 'f' then false when '0' then false
             else null
           end as discontinued_value,
           nullif(i.raw ->> 'itemNote', '') as notes_value,
           jsonb_strip_nulls(jsonb_build_object(
             'origin', 'plm_item_autoflow',
             'coldlion_created_by', nullif(i.raw ->> 'createdUser', ''),
             'coldlion_created_at', nullif(i.raw ->> 'createdTime', ''),
             'coldlion_division', nullif(i.raw ->> 'divisionCode', ''),
             'coldlion_vendor_code', nullif(i.raw ->> 'vendorCode', ''),
             'coldlion_royalty_code', nullif(i.raw ->> 'royaltyCode', ''),
             'coldlion_size_range', nullif(i.raw ->> 'sizeRangeCode', '')
           )) as row_data_value
    from plm.item i
    left join core.licensor lic on lic.id = i.licensor_id
    where i.created_at >= p_cutoff
      and coalesce(btrim(i.style_number), btrim(i.item_number)) <> ''
      and not exists (
        select 1 from public.style_tracker_rows r
        where upper(btrim(r.sku)) = upper(btrim(coalesce(i.style_number, i.item_number)))
      )
      and not exists (
        select 1 from plm.style_tracker_item_bridge b
        where b.plm_item_id = i.id
      )
      -- #4956 assortment skip, half 1: a marked head is never eligible. The live
      -- parent marker is the head's own pre_pack_code; components carry none.
      and not exists (
        select 1
        from coldlion.item_detail d
        where d.company_code = i.raw ->> 'companyCode'
          and d.division_code = i.raw ->> 'divisionCode'
          and btrim(d.item_no) = btrim(coalesce(nullif(btrim(i.style_number), ''), btrim(i.item_number)))
          and nullif(btrim(d.pre_pack_code), '') is not null
      )
      -- #4956 assortment skip, half 2: without an itemDetails row the item is
      -- undecided, not cleared. Decide it only once a masters projection has
      -- completed after the item landed; items ColdLion never details pass this
      -- gate as soon as any projection has run past their landing time.
      and (
        exists (
          select 1
          from coldlion.item_detail d
          where d.company_code = i.raw ->> 'companyCode'
            and d.division_code = i.raw ->> 'divisionCode'
            and btrim(d.item_no) = btrim(coalesce(nullif(btrim(i.style_number), ''), btrim(i.item_number)))
        )
        or i.created_at <= v_masters_fetched_at
      )
    order by upper(btrim(coalesce(i.style_number, i.item_number))), i.created_at, i.id
  )
  select count(*) into v_eligible from deduped;

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
  where source_workbook_id = '1ZL6cEwydC0cWSGP2I92uILn1ixILr_qAeDfDfD6F214'
    and source_sheet = 'License.Style';

  -- Owner direction 2026-10-29: EH001 is the one generic division; CW001 and SP001 are licensed.
  select coalesce(max(source_row_number), 2) + 1 into v_next_generic_row_number
  from public.style_tracker_rows
  where source_workbook_id = '1ZL6cEwydC0cWSGP2I92uILn1ixILr_qAeDfDfD6F214'
    and source_sheet = 'Generic.Style';

  with deduped as (
    select distinct on (upper(btrim(coalesce(i.style_number, i.item_number))))
           i.id as plm_item_id,
           btrim(coalesce(i.style_number, i.item_number)) as sku_value,
           i.created_at,
           coalesce(nullif(i.raw ->> 'itemDisplayDesc', ''), nullif(i.raw ->> 'itemDesc', ''), nullif(i.description, '')) as desc_value,
           lic.name as licensor_value,
           case lower(btrim(i.raw ->> 'itemDiscontinued'))
             when 'y' then true when 'true' then true when 't' then true when '1' then true
             when 'n' then false when 'false' then false when 'f' then false when '0' then false
             else null
           end as discontinued_value,
           nullif(i.raw ->> 'itemNote', '') as notes_value,
           jsonb_strip_nulls(jsonb_build_object(
             'origin', 'plm_item_autoflow',
             'coldlion_created_by', nullif(i.raw ->> 'createdUser', ''),
             'coldlion_created_at', nullif(i.raw ->> 'createdTime', ''),
             'coldlion_division', nullif(i.raw ->> 'divisionCode', ''),
             'coldlion_vendor_code', nullif(i.raw ->> 'vendorCode', ''),
             'coldlion_royalty_code', nullif(i.raw ->> 'royaltyCode', ''),
             'coldlion_size_range', nullif(i.raw ->> 'sizeRangeCode', '')
           )) as row_data_value,
           coalesce((i.raw ->> 'divisionCode') = 'EH001', false) as is_generic
    from plm.item i
    left join core.licensor lic on lic.id = i.licensor_id
    where i.created_at >= p_cutoff
      and coalesce(btrim(i.style_number), btrim(i.item_number)) <> ''
      and not exists (
        select 1 from public.style_tracker_rows r
        where upper(btrim(r.sku)) = upper(btrim(coalesce(i.style_number, i.item_number)))
      )
      and not exists (
        select 1 from plm.style_tracker_item_bridge b
        where b.plm_item_id = i.id
      )
      -- #4956 assortment skip, half 1 (identical to the counting CTE above).
      and not exists (
        select 1
        from coldlion.item_detail d
        where d.company_code = i.raw ->> 'companyCode'
          and d.division_code = i.raw ->> 'divisionCode'
          and btrim(d.item_no) = btrim(coalesce(nullif(btrim(i.style_number), ''), btrim(i.item_number)))
          and nullif(btrim(d.pre_pack_code), '') is not null
      )
      -- #4956 assortment skip, half 2 (identical to the counting CTE above).
      and (
        exists (
          select 1
          from coldlion.item_detail d
          where d.company_code = i.raw ->> 'companyCode'
            and d.division_code = i.raw ->> 'divisionCode'
            and btrim(d.item_no) = btrim(coalesce(nullif(btrim(i.style_number), ''), btrim(i.item_number)))
        )
        or i.created_at <= v_masters_fetched_at
      )
    order by upper(btrim(coalesce(i.style_number, i.item_number))), i.created_at, i.id
  ),
  capped as (
    select plm_item_id, sku_value, created_at, desc_value, licensor_value,
           discontinued_value, notes_value, row_data_value, is_generic
    from deduped
    order by created_at, plm_item_id
    limit v_max_rows
  )
  insert into public.style_tracker_rows (
    source_workbook_id, source_sheet, source_row_number, tracker_type, sku,
    description, licensor, discontinued, notes, row_data
  )
  select
    '1ZL6cEwydC0cWSGP2I92uILn1ixILr_qAeDfDfD6F214',
    case when c.is_generic then 'Generic.Style' else 'License.Style' end,
    case when c.is_generic then v_next_generic_row_number else v_next_row_number end
      + row_number() over (partition by c.is_generic order by c.created_at, c.plm_item_id) - 1,
    case when c.is_generic then 'generic' else 'licensed' end,
    c.sku_value,
    c.desc_value,
    c.licensor_value,
    c.discontinued_value,
    c.notes_value,
    c.row_data_value
  from capped c;

  get diagnostics inserted_count = row_count;

  -- Link the new rows through the existing, already-reviewed matcher: unique
  -- upper(trim(sku)) = upper(trim(coalesce(style_number, item_number))) wins, ambiguous
  -- SKUs stay unmatched for manual linking, exactly like hand-added rows. The refresh is
  -- a full-tracker reconcile, so skip it on zero-insert nights.
  if inserted_count > 0 then
    perform plm.refresh_style_tracker_item_bridge();
  end if;

  eligible_count := v_eligible;
  deferred_count := v_deferred;
  return next;
end;
$fn$;

revoke all on function public.sync_new_items_into_style_tracker(boolean, timestamptz) from public, anon, authenticated;
grant execute on function public.sync_new_items_into_style_tracker(boolean, timestamptz) to service_role;

-- One-time correction (owner 2026-10-29: "all EH001 items should be in
-- Generic"): move every Licensed row whose bridged item, or auto-flow origin,
-- is division EH001. Idempotent: zero rows once corrected.
with wrong as (
  select r.id,
         row_number() over (order by r.source_row_number, r.id) as rn
  from public.style_tracker_rows r
  where r.tracker_type = 'licensed'
    and (r.row_data ->> 'coldlion_division' = 'EH001'
         or exists (select 1
                      from plm.style_tracker_item_bridge b
                      join plm.item i on i.id = b.plm_item_id
                     where b.style_tracker_row_id = r.id
                       and i.raw ->> 'divisionCode' = 'EH001'))
), base as (
  select coalesce(max(source_row_number), 2) as n
  from public.style_tracker_rows
  where source_workbook_id = '1ZL6cEwydC0cWSGP2I92uILn1ixILr_qAeDfDfD6F214'
    and source_sheet = 'Generic.Style'
)
update public.style_tracker_rows r
   set tracker_type = 'generic',
       source_sheet = 'Generic.Style',
       source_row_number = base.n + wrong.rn
  from wrong, base
 where r.id = wrong.id;
