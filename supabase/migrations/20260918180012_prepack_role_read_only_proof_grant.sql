-- Issue #3191 (for the #2611 live proof).
--
-- The read-only proof identity supabase_read_only_user already reads
-- plm.item_missing_attribution (via pg_read_all_data), but the view calls
-- plm.prepack_role, and function EXECUTE is checked against the querying
-- role, so the proof fails with "permission denied for function prepack_role".
--
-- Narrowest fix: EXECUTE on this one function only. prepack_role is a STABLE,
-- read-only SQL function returning 'head' / 'member' / null; it writes nothing.
-- No role membership (e.g. in authenticated) is granted.

grant execute on function plm.prepack_role(text, text, text) to supabase_read_only_user;
