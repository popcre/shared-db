-- Live proof for #2848 (migration 20260914155226). Catalog reads only.
-- anon and authenticated hold no SELECT/INSERT/UPDATE/DELETE on any of the four
-- tables (so every Data API request as those roles is refused), RLS stays on,
-- and service_role keeps INSERT on scanner_ai_ignores for the Edge Function.
-- has_table_privilege with a list is true if ANY listed privilege is held.
select (
  count(*) = 4
  and bool_and(not has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE'))
  and bool_and(not has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE'))
  and bool_and(c.relrowsecurity)
  and bool_or(c.relname = 'scanner_ai_ignores' and has_table_privilege('service_role', c.oid, 'INSERT'))
) as passed
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname in ('ai_sentinel_cleanup_log', 'dam_search_documents', 'dam_search_synonyms', 'scanner_ai_ignores')
