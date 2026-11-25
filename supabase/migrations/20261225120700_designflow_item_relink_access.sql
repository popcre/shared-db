-- #4707: owner-ruled correction of DesignFlow item copy links.
-- The reconcile never changes a copy's canonical ColdLion link. On 2026-11-24
-- ColdLion added items that (a) gave 11 unlinked copies their first unique
-- match and (b) duplicated 39 linked numbers in SP001. Owner ruling (Albert,
-- 2026-11-24, applying the 2026-08-19 "each division produces" ruling): the
-- product type decides the division, so those 39 belong to their SP001 item.
-- The Data Syncing runtime gets no new table right. It may call one owner
-- function that, for the exact list its verified plan reported, checks each
-- row still matches the plan and one of the two rules, saves before-images,
-- removes the copied child rows of the old item, and sets the new link. A
-- private log lets a second owner function put the old links back by run id;
-- the runtime's existing rollback then restores the child rows.
-- derived-from: none

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create table plm.designflow_relink_log (
  run_id uuid not null,
  legacy_item_id integer not null references plm.designflow_item(legacy_item_id),
  from_item_id uuid,
  from_disposition text not null,
  to_item_id uuid not null,
  rule text not null check (rule in ('first_unique_match', 'product_type_division')),
  relinked_at timestamptz not null default now(),
  rolled_back_at timestamptz,
  primary key (run_id, legacy_item_id)
);
alter table plm.designflow_relink_log enable row level security;
revoke all on plm.designflow_relink_log from public, anon, authenticated;

-- ColdLion MG01 product type to the licensed division that produces it
-- (business-rules/merchandise-and-product-taxonomy.md, 2026-08-19).
create function plm.designflow_product_type_division(p_mg01 text)
returns text language sql immutable set search_path = '' as $$
  select case
    when upper(btrim(p_mg01)) in ('A','B','C','D','E','F','G','H','J','K','M') then 'CW001'
    when upper(btrim(p_mg01)) in ('N','P','Q','R','S','T','U','V','W') then 'SP001'
  end
$$;
revoke all on function plm.designflow_product_type_division(text) from public, anon, authenticated;
grant execute on function plm.designflow_product_type_division(text) to designflow_prod_data_sync_grants;

create function plm.designflow_relink_items(p_run_id uuid, p_expected jsonb)
returns integer[]
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_bad integer;
  v_done integer[];
begin
  if p_run_id is null or p_expected is null or jsonb_typeof(p_expected) <> 'array'
     or jsonb_array_length(p_expected) = 0 then
    raise exception 'designflow_relink_items: run id and a non-empty expected list are required';
  end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'designflow_relink_items: must run in a read committed transaction'
      using errcode = 'P0001', hint = 'ITEM_RELINK_ISOLATION';
  end if;
  lock table plm.designflow_item in share row exclusive mode;
  lock table plm.item_merch_group, plm.item_custom_value, plm.item_price, plm.licensing_attachment
    in share row exclusive mode;

  drop table if exists pg_temp.relink;
  create temporary table pg_temp.relink on commit drop as
  select e.legacy_item_id, e.from_item_id, e.to_item_id, t.match_disposition as from_disposition,
    case when e.from_item_id is null then 'first_unique_match' else 'product_type_division' end as rule,
    (
      t.canonical_item_id is not distinct from e.from_item_id
      and n.id is not null and n.source_system = 'coldlion'
      and upper(btrim(n.item_number)) = upper(btrim(t.legacy_item_number))
      and not exists (select from plm.designflow_item o where o.canonical_item_id = e.to_item_id)
      and case
        when e.from_item_id is null then
          t.match_disposition = 'unmatched_number'
          and (select count(*) from plm.item c where c.source_system = 'coldlion'
               and upper(btrim(c.item_number)) = upper(btrim(t.legacy_item_number))) = 1
        else
          t.match_disposition = 'eligible'
          and f.source_system = 'coldlion'
          and upper(btrim(f.item_number)) = upper(btrim(n.item_number))
          and n.raw->>'divisionCode' = plm.designflow_product_type_division(n.raw->>'merchGroup01')
          and f.raw->>'divisionCode' is distinct from n.raw->>'divisionCode'
          and (select count(*) from plm.item c where c.source_system = 'coldlion'
               and upper(btrim(c.item_number)) = upper(btrim(n.item_number))
               and c.raw->>'divisionCode' = n.raw->>'divisionCode') = 1
      end
      and n.raw->>'divisionCode' in ('CW001', 'EH001', 'SP001')
      and n.raw->>'nonInventoryItem' = 'N'
    ) as ok
  from jsonb_to_recordset(p_expected) e(legacy_item_id integer, from_item_id uuid, to_item_id uuid)
  left join plm.designflow_item t on t.legacy_item_id = e.legacy_item_id
  left join plm.item n on n.id = e.to_item_id
  left join plm.item f on f.id = e.from_item_id;

  select count(*) into v_bad from pg_temp.relink where ok is not true;
  if v_bad <> 0 or (select count(distinct legacy_item_id) from pg_temp.relink) <> jsonb_array_length(p_expected)
     or (select count(distinct to_item_id) from pg_temp.relink) <> jsonb_array_length(p_expected) then
    raise exception 'designflow_relink_items: % row(s) differ from the verified plan or the owner rule', v_bad
      using errcode = 'P0001', hint = 'ITEM_RELINK_REFUSED';
  end if;
  if exists (select from plm.licensing_attachment a join pg_temp.relink r on a.item_id = r.from_item_id) then
    raise exception 'designflow_relink_items: an old item carries licensing attachments'
      using errcode = 'P0001', hint = 'ITEM_RELINK_REFUSED';
  end if;

  insert into plm.designflow_reconcile_before_image (run_id, target_table, operation, target_key, before_row)
  select p_run_id, 'designflow_item', 'update', jsonb_build_object('legacy_item_id', t.legacy_item_id), to_jsonb(t)
  from plm.designflow_item t join pg_temp.relink r using (legacy_item_id);
  insert into plm.designflow_reconcile_before_image (run_id, target_table, operation, target_key, before_row)
  select p_run_id, 'item_merch_group', 'delete',
    jsonb_build_object('item_id', x.item_id, 'slot_number', x.slot_number), to_jsonb(x)
  from plm.item_merch_group x join pg_temp.relink r on x.item_id = r.from_item_id;
  insert into plm.designflow_reconcile_before_image (run_id, target_table, operation, target_key, before_row)
  select p_run_id, 'item_custom_value', 'delete',
    jsonb_build_object('item_id', x.item_id, 'slot_kind', x.slot_kind, 'slot_number', x.slot_number), to_jsonb(x)
  from plm.item_custom_value x join pg_temp.relink r on x.item_id = r.from_item_id;
  insert into plm.designflow_reconcile_before_image (run_id, target_table, operation, target_key, before_row)
  select p_run_id, 'item_price', 'delete',
    jsonb_build_object('item_id', x.item_id, 'price_level', x.price_level), to_jsonb(x)
  from plm.item_price x join pg_temp.relink r on x.item_id = r.from_item_id;

  delete from plm.item_merch_group x using pg_temp.relink r where x.item_id = r.from_item_id;
  delete from plm.item_custom_value x using pg_temp.relink r where x.item_id = r.from_item_id;
  delete from plm.item_price x using pg_temp.relink r where x.item_id = r.from_item_id;

  insert into plm.designflow_relink_log (run_id, legacy_item_id, from_item_id, from_disposition, to_item_id, rule)
  select p_run_id, legacy_item_id, from_item_id, from_disposition, to_item_id, rule from pg_temp.relink;

  with u as (
    update plm.designflow_item t set canonical_item_id = r.to_item_id, match_disposition = 'eligible'
    from pg_temp.relink r where t.legacy_item_id = r.legacy_item_id returning t.legacy_item_id
  ) select coalesce(array_agg(legacy_item_id order by legacy_item_id), '{}') into v_done from u;
  return v_done;
end
$$;
revoke all on function plm.designflow_relink_items(uuid, jsonb) from public, anon, authenticated;
grant execute on function plm.designflow_relink_items(uuid, jsonb) to designflow_prod_data_sync_grants;

-- Put a relink run's old links back. Refuses unless every item still carries
-- the link this run set and its new item has no copied child rows yet (roll
-- back any later reconcile first). The runtime's rollback then restores the
-- old child rows from this run's before-images.
create function plm.designflow_relink_items_rollback(p_run_id uuid)
returns integer[]
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_done integer[];
begin
  if p_run_id is null then
    raise exception 'designflow_relink_items_rollback: run id is required';
  end if;
  lock table plm.designflow_item in share row exclusive mode;
  lock table plm.item_merch_group, plm.item_custom_value, plm.item_price, plm.licensing_attachment
    in share row exclusive mode;
  if not exists (select from plm.designflow_relink_log where run_id = p_run_id and rolled_back_at is null) then
    return '{}';
  end if;
  if exists (
    select from plm.designflow_relink_log l
    left join plm.designflow_item t on t.legacy_item_id = l.legacy_item_id
    where l.run_id = p_run_id and l.rolled_back_at is null
      and (t.canonical_item_id is distinct from l.to_item_id
        or exists (select from plm.item_merch_group x where x.item_id = l.to_item_id)
        or exists (select from plm.item_custom_value x where x.item_id = l.to_item_id)
        or exists (select from plm.item_price x where x.item_id = l.to_item_id)
        or exists (select from plm.licensing_attachment x where x.item_id = l.to_item_id))
  ) then
    raise exception 'designflow_relink_items_rollback: a later run changed these items; roll it back first'
      using errcode = 'P0001', hint = 'ITEM_RECONCILE_ROLLBACK_SUPERSEDED';
  end if;
  with u as (
    update plm.designflow_item t set canonical_item_id = l.from_item_id, match_disposition = l.from_disposition
    from plm.designflow_relink_log l
    where l.run_id = p_run_id and l.rolled_back_at is null and t.legacy_item_id = l.legacy_item_id
    returning t.legacy_item_id
  ) select coalesce(array_agg(legacy_item_id order by legacy_item_id), '{}') into v_done from u;
  update plm.designflow_relink_log set rolled_back_at = now() where run_id = p_run_id and rolled_back_at is null;
  return v_done;
end
$$;
revoke all on function plm.designflow_relink_items_rollback(uuid) from public, anon, authenticated;
grant execute on function plm.designflow_relink_items_rollback(uuid) to designflow_prod_data_sync_grants;

commit;
