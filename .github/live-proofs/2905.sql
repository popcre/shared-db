-- Live proof for #2905 (migration 20260914172031). Read-only.
-- The probe role cannot EXECUTE api.db_data_admin_scraped_source_inventory
-- (granted to authenticated only), so this proves the live outcome from what
-- the function is built on:
--   1. the migration is in production's ledger;
--   2. the live function definition carries the canonical licensor group
--      (licensor_group_key / licensor_group_name, one 'Licensor not yet
--      determined' group, Disney / Marvel / Lucasfilm-Star Wars kept separate,
--      unresolved keys never mapped to Disney), keeps the Licensing Manager
--      gate, and classifies NBCU picker rows as Submissions, others Creative;
--   3. the NBCU rows that definition classifies as Submissions number exactly
--      129 at capture rank 1 (same ranking as the function), and every
--      remaining NBCU row is Creative, so NBCUniversal has both purposes.
with fn as (
  select pg_get_functiondef(
    'api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure
  ) as def
), nbcu_ranked as (
  select p.source_kind,
         row_number() over (
           partition by p.property_key
           order by c.source_captured_at desc, p.source_captured_at desc, p.capture_id::text desc
         ) as capture_rank
  from plm.nbcu_property p
  join plm.nbcu_capture c on c.id = p.capture_id
  where c.status = 'complete'
), nbcu as (
  select count(*) filter (where source_kind in ('property', 'franchise_asset')) as submissions,
         count(*) filter (where source_kind not in ('property', 'franchise_asset')) as creative
  from nbcu_ranked
  where capture_rank = 1
)
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260914172031')
  and n.submissions = 129
  and n.creative > 0
  and (select count(*) from fn
       where def like '%licensor_group_key%'
         and def like '%licensor_group_name%'
         and def like '%''Licensor not yet determined''%'
         and def like '%else ''unresolved''%'
         and def like '%in (''disney'', ''disney-opa'') then ''disney''%'
         and def like '%in (''marvel'', ''marvel-opa'', ''marvel-asgard-creative'') then ''marvel''%'
         and def like '%in (''lucasfilm-star-wars'', ''lucasfilm-star-wars-opa'') then ''lucasfilm-star-wars''%'
         and def not like '%unresolved'') then ''disney''%'
         and def not like '%conflict'') then ''disney''%'
         and def like '%when p.source_kind in (''property'', ''franchise_asset'')%'
         and def like '%then ''Submissions'' else ''Creative'' end%'
         and def like '%app.require_licensing_manager_access()%') = 1
) as passed
from nbcu n
