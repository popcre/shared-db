-- #2421 installed-state probe only. Read-only; application acceptance separately
-- requires the deployed differential worker and a full week of zero drift.
WITH installed AS (
  SELECT oid,prosecdef FROM pg_proc
  WHERE oid=to_regprocedure('public.rebuild_style_groups_batch(uuid,integer,timestamptz)')
), clocks AS (
  SELECT count(*) AS n FROM pg_attribute
  WHERE attrelid IN ('public.assets'::regclass,'public.style_groups'::regclass)
    AND attname='style_group_changed_at' AND attnotnull AND NOT attisdropped
), triggers AS (
  SELECT count(*) AS n FROM pg_trigger WHERE NOT tgisinternal AND tgenabled='O'
    AND tgname IN ('assets_style_group_change_clock','style_groups_style_group_change_clock','style_group_tags_change_clock')
)
SELECT (
  EXISTS(SELECT FROM supabase_migrations.schema_migrations WHERE version='20261011125719')
  AND (SELECT n=2 FROM clocks) AND (SELECT n=3 FROM triggers)
  AND EXISTS(SELECT FROM installed WHERE prosecdef
    AND has_function_privilege('service_role',oid,'EXECUTE')
    AND NOT has_function_privilege('anon',oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',oid,'EXECUTE'))
  AND to_regprocedure('public.rebuild_style_groups_batch(uuid,integer)') IS NOT NULL
  AND to_regprocedure('public.clear_style_group_batch(uuid,integer)') IS NOT NULL
  AND to_regclass('public.assets_style_group_changed_at_idx') IS NOT NULL
  AND to_regclass('public.style_groups_style_group_changed_at_idx') IS NOT NULL
  AND to_regclass('public.assets_ungrouped_style_cursor_idx') IS NOT NULL
  AND pg_get_functiondef('public.queue_nightly_rebuild_style_groups()'::regprocedure) LIKE '%last_successful_cutoff%'
) AS passed
