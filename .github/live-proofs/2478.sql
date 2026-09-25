-- Live proof for #2478 (migration 20260925061508, claim #2745). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. public.style_group_key_for_sku(text) exists, is IMMUTABLE and SECURITY INVOKER,
--      and is not executable by anon or authenticated
--   3. both consumers, public.rebuild_style_groups_batch and
--      public.reconcile_style_group_drift, now call the shared helper and remain
--      SECURITY DEFINER
--   4. the helper derives the SKU folder the rule defines: the first alphanumeric
--      segment of 7+ characters mixing letters and digits, never the file name
with helper as (
  select p.oid, p.provolatile, p.prosecdef
  from pg_proc p
  where p.oid = to_regprocedure('public.style_group_key_for_sku(text)')
), consumers as (
  select p.oid, p.proname, p.prosecdef, pg_get_functiondef(p.oid) as def
  from pg_proc p
  where p.oid in (
    to_regprocedure('public.rebuild_style_groups_batch(uuid, integer)'),
    to_regprocedure('public.reconcile_style_group_drift(integer)')
  )
)
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260925061508')
  and (select count(*) from helper) = 1
  and (select bool_and(provolatile = 'i' and not prosecdef) from helper)
  and (select bool_and(not has_function_privilege('anon', oid, 'EXECUTE')
                       and not has_function_privilege('authenticated', oid, 'EXECUTE')) from helper)
  and (select count(*) from consumers) = 2
  and (select bool_and(prosecdef and def ~ 'style_group_key_for_sku\s*\(') from consumers)
  and (select bool_and(has_function_privilege('postgres', oid, 'EXECUTE')) from consumers)
  and public.style_group_key_for_sku('Licensor/Property/AB12345CD/art/AB12345CD01.psd') = 'AB12345CD'
  and public.style_group_key_for_sku('Art/ab12/AB12345CD01.psd') is null
) as passed
