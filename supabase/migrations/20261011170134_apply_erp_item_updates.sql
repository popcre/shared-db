-- =====================================================================================
-- Issue #4167 - PopDAM ERP apply: update an item's assets and style group in one call
-- (PopDAM u2giants/popdam3#204; app-side batching landed in popdam3 PR #309).
-- Claim #4179 reserves version 20261011170134 and exactly one object:
--
--   function public.apply_erp_item_updates(jsonb)   (new)
--
-- derived-from: none
--
-- WHAT IT DOES
-- ---------------------------------------------------------------------------------
-- The PopDAM worker (apps/worker/src/handlers/erp.ts) today sends, per ERP item, one
-- PATCH to public.assets and one to public.style_groups, both matched on
-- (sku, division_code) and, for assets, is_deleted = false. The two writes are not
-- atomic and cost two round trips per item, 100 items per page.
--
-- This function takes the whole page as a JSON array and applies every item's asset
-- and style-group update inside the caller's single transaction, so either the whole
-- page lands or none of it does. It returns one result object per input item, in
-- input order: {asset_count, group_count, asset_id, group_id}, where *_id is one
-- matched row id (or null), which the worker uses as the audit-log target exactly as
-- it used the first returned row before.
--
-- Input element shape: {"sku": text, "division_code": text, "updates": {field: text}}.
-- Only these fields may appear in "updates" (every one is a text column on both
-- tables): mg01_code, mg02_code, mg03_code, size_code, licensor_code, property_code,
-- division_code, product_category, cover_description. Any other key, a missing sku,
-- an empty updates object, a non-array payload or more than 500 items raises, and the
-- whole call is rolled back. Matching keeps the worker's semantics: plain equality on
-- sku and division_code (a null division_code matches nothing).
--
-- The erp_enrichment_log insert stays in the worker: it needs the ids this returns.
-- Execute is service_role only (the worker's client).
-- =====================================================================================

create function public.apply_erp_item_updates(p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
set statement_timeout to '60s'
as $function$
declare
  c_allowed constant text[] := array[
    'mg01_code','mg02_code','mg03_code','size_code','licensor_code',
    'property_code','division_code','product_category','cover_description'];
  v_item     jsonb;
  v_u        jsonb;
  v_sku      text;
  v_div      text;
  v_bad      text;
  v_a_ids    uuid[];
  v_g_ids    uuid[];
  v_results  jsonb := '[]'::jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'p_items must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 500 then
    raise exception 'p_items has % items; the limit is 500', jsonb_array_length(p_items)
      using errcode = '22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'each item must be a JSON object' using errcode = '22023';
    end if;
    v_sku := nullif(btrim(coalesce(v_item ->> 'sku', '')), '');
    v_div := v_item ->> 'division_code';
    v_u   := v_item -> 'updates';
    if v_sku is null then
      raise exception 'item sku is required' using errcode = '22023';
    end if;
    if v_u is null or jsonb_typeof(v_u) <> 'object' or v_u = '{}'::jsonb then
      raise exception 'item % updates must be a non-empty JSON object', v_sku using errcode = '22023';
    end if;
    select k into v_bad from jsonb_object_keys(v_u) as k where k <> all (c_allowed) limit 1;
    if v_bad is not null then
      raise exception 'item % updates field % is not allowed', v_sku, v_bad using errcode = '22023';
    end if;
    select k into v_bad from jsonb_each(v_u) as e(k, v)
     where jsonb_typeof(v) not in ('string', 'null') limit 1;
    if v_bad is not null then
      raise exception 'item % updates field % must be a string or null', v_sku, v_bad using errcode = '22023';
    end if;

    with upd as (
      update public.assets a set
        mg01_code         = case when v_u ? 'mg01_code'         then v_u ->> 'mg01_code'         else a.mg01_code end,
        mg02_code         = case when v_u ? 'mg02_code'         then v_u ->> 'mg02_code'         else a.mg02_code end,
        mg03_code         = case when v_u ? 'mg03_code'         then v_u ->> 'mg03_code'         else a.mg03_code end,
        size_code         = case when v_u ? 'size_code'         then v_u ->> 'size_code'         else a.size_code end,
        licensor_code     = case when v_u ? 'licensor_code'     then v_u ->> 'licensor_code'     else a.licensor_code end,
        property_code     = case when v_u ? 'property_code'     then v_u ->> 'property_code'     else a.property_code end,
        division_code     = case when v_u ? 'division_code'     then v_u ->> 'division_code'     else a.division_code end,
        product_category  = case when v_u ? 'product_category'  then v_u ->> 'product_category'  else a.product_category end,
        cover_description = case when v_u ? 'cover_description' then v_u ->> 'cover_description' else a.cover_description end
      where a.sku = v_sku and a.division_code = v_div and a.is_deleted = false
      returning a.id
    )
    select coalesce(array_agg(id), '{}'::uuid[]) into v_a_ids from upd;

    with upd as (
      update public.style_groups g set
        mg01_code         = case when v_u ? 'mg01_code'         then v_u ->> 'mg01_code'         else g.mg01_code end,
        mg02_code         = case when v_u ? 'mg02_code'         then v_u ->> 'mg02_code'         else g.mg02_code end,
        mg03_code         = case when v_u ? 'mg03_code'         then v_u ->> 'mg03_code'         else g.mg03_code end,
        size_code         = case when v_u ? 'size_code'         then v_u ->> 'size_code'         else g.size_code end,
        licensor_code     = case when v_u ? 'licensor_code'     then v_u ->> 'licensor_code'     else g.licensor_code end,
        property_code     = case when v_u ? 'property_code'     then v_u ->> 'property_code'     else g.property_code end,
        division_code     = case when v_u ? 'division_code'     then v_u ->> 'division_code'     else g.division_code end,
        product_category  = case when v_u ? 'product_category'  then v_u ->> 'product_category'  else g.product_category end,
        cover_description = case when v_u ? 'cover_description' then v_u ->> 'cover_description' else g.cover_description end
      where g.sku = v_sku and g.division_code = v_div
      returning g.id
    )
    select coalesce(array_agg(id), '{}'::uuid[]) into v_g_ids from upd;

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'asset_count', cardinality(v_a_ids),
      'group_count', cardinality(v_g_ids),
      'asset_id',    v_a_ids[1],
      'group_id',    v_g_ids[1]));
  end loop;

  return v_results;
end;
$function$;

revoke all on function public.apply_erp_item_updates(jsonb) from public;
revoke all on function public.apply_erp_item_updates(jsonb) from anon;
revoke all on function public.apply_erp_item_updates(jsonb) from authenticated;
grant execute on function public.apply_erp_item_updates(jsonb) to service_role;

comment on function public.apply_erp_item_updates(jsonb) is
  'shared-db#4167: apply a page of ERP item updates to public.assets and public.style_groups '
  'atomically; returns per-item {asset_count, group_count, asset_id, group_id} in input order.';
