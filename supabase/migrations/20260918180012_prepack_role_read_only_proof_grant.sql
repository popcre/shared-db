-- Issue #3191 (for the #2611 live proof).
--
-- The read-only proof identity supabase_read_only_user already reads
-- plm.item_missing_attribution (via pg_read_all_data), but the view calls
-- plm.prepack_role, and function EXECUTE is checked against the querying
-- role, so the proof fails with "permission denied for function prepack_role".
--
-- Narrowest fix: EXECUTE on this one function only. No role membership
-- (e.g. in authenticated) is granted. prepack_role is a STABLE, read-only SQL
-- function returning 'head' / 'member' / null; it writes nothing.
--
-- What this confers: prepack_role is SECURITY DEFINER, so it reads the
-- coldlion prod_history_component landing tables as its owner. Those tables are
-- RLS-enabled with no policies, so supabase_read_only_user cannot read their
-- rows directly (pg_read_all_data does not bypass RLS). After this grant it can
-- learn one derived fact per item number it asks about: whether that item is a
-- prepack head, a prepack member, or neither. No component row is returned.
--
-- supabase_read_only_user is provisioned by the Supabase platform, not by any
-- migration in this repository, so the grant is guarded: a target without the
-- role (a local or CI stack) skips it with a notice instead of aborting.
-- Production has the role; the #2611 live proof there is the evidence it landed.

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    grant execute on function plm.prepack_role(text, text, text) to supabase_read_only_user;
  else
    raise notice 'supabase_read_only_user does not exist on this target; prepack_role grant skipped';
  end if;
end $$;
