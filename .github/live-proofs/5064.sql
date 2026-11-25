-- #5064 read-only live proof: the sync prefers ColdLion's full description and
-- re-asserts it, and no ColdLion-linked Master Data line differs from it.
select
  pg_catalog.pg_get_functiondef('public.sync_new_items_into_style_tracker(boolean,timestamptz)'::regprocedure)
    like '%pre_coldlion_description%'
  and not exists (
    select 1
      from public.style_tracker_rows r
      join plm.style_tracker_item_bridge b on b.style_tracker_row_id = r.id
      join plm.item i on i.id = b.plm_item_id
     where i.source_system = 'coldlion'
       and coalesce(nullif(i.raw ->> 'itemDesc', ''), nullif(i.raw ->> 'itemDisplayDesc', ''), nullif(i.description, '')) is not null
       and r.description is distinct from coalesce(nullif(i.raw ->> 'itemDesc', ''), nullif(i.raw ->> 'itemDisplayDesc', ''), nullif(i.description, '')))
  as passed;
