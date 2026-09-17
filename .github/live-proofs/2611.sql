-- Live proof for #2611 (migration 20260917081048, PR #2823). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. plm.prepack_role(text, text, text) exists and view plm.item_missing_attribution
--      exists, calls it, and is not readable by anon
--   3. none of the seven recorded licensed-division prepack heads
--      (docs/verification/prepack-exclusion-20260911.md) appears in the view,
--      while at least one of them is still in plm.item and classified as a head,
--      so the exclusion is shown to bite rather than to pass on absent rows
with heads(item_number) as (
  values ('AA814DYCR01'), ('AAH62NBEX01'), ('AAH62WBLB01'), ('VF122FKFK01'),
         ('VF122FKFK02'), ('VF122FKFK03'), ('VFS22FKFK01')
), v as (
  select c.oid
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'plm' and c.relname = 'item_missing_attribution' and c.relkind = 'v'
)
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260917081048')
  and to_regprocedure('plm.prepack_role(text,text,text)') is not null
  and (select count(*) from v) = 1
  and (select bool_and(pg_get_viewdef(oid) like '%prepack_role%') from v)
  and (select bool_and(not has_table_privilege('anon', oid, 'SELECT')) from v)
  and not exists (
    select 1 from plm.item_missing_attribution m join heads h on h.item_number = m.item_number
  )
  and exists (
    select 1 from plm.item i join heads h on h.item_number = i.item_number
    where plm.prepack_role(i.item_number, i.raw ->> 'companyCode', i.raw ->> 'divisionCode') = 'head'
  )
) as passed
