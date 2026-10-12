-- #2421 installed-state probe only. Read-only; application acceptance separately
-- requires the deployed differential worker and a full week of zero drift.
WITH installed AS (
  SELECT oid,prosecdef,provolatile,proconfig FROM pg_proc
  WHERE oid=to_regprocedure('public.rebuild_style_groups_batch(uuid,integer,timestamptz)')
), clocks AS (
  SELECT count(*) AS n FROM pg_attribute
  WHERE attrelid IN ('public.assets'::regclass,'public.style_groups'::regclass)
    AND attname='style_group_changed_at' AND atttypid='timestamptz'::regtype
    AND attnotnull AND NOT attisdropped
), triggers AS (
  SELECT count(*) AS n FROM (VALUES
    ('public.assets','assets_style_group_change_clock','public.stamp_style_group_asset_change()',23),
    ('public.style_groups','style_groups_style_group_change_clock','public.stamp_style_group_definition_change()',23),
    ('public.style_group_tags','style_group_tags_change_clock','public.touch_style_group_tag_change()',29)
  ) e(relation,name,signature,type)
  JOIN pg_trigger t ON t.tgrelid=to_regclass(e.relation) AND t.tgname=e.name
    AND t.tgfoid=to_regprocedure(e.signature) AND t.tgtype=e.type
    AND t.tgnargs=0 AND NOT t.tgisinternal AND t.tgenabled='O'
), indexes AS (
  SELECT count(*) AS n FROM (VALUES
    ('public.assets_style_group_changed_at_idx','CREATE INDEX assets_style_group_changed_at_idx ON public.assets USING btree (style_group_changed_at, id) WHERE (is_deleted = false)'),
    ('public.style_groups_style_group_changed_at_idx','CREATE INDEX style_groups_style_group_changed_at_idx ON public.style_groups USING btree (style_group_changed_at, id)'),
    ('public.assets_ungrouped_style_cursor_idx','CREATE INDEX assets_ungrouped_style_cursor_idx ON public.assets USING btree (id) WHERE ((is_deleted = false) AND (style_group_id IS NULL))'),
    ('public.assets_style_group_id_active_idx','CREATE INDEX assets_style_group_id_active_idx ON public.assets USING btree (style_group_id, id) WHERE ((is_deleted = false) AND (style_group_id IS NOT NULL))')
  ) e(name,definition)
  JOIN pg_index i ON i.indexrelid=to_regclass(e.name)
    AND i.indisvalid AND i.indisready AND pg_get_indexdef(i.indexrelid)=e.definition
)
SELECT (
  EXISTS(SELECT FROM supabase_migrations.schema_migrations WHERE version='20261012012727')
  AND (SELECT n=2 FROM clocks) AND (SELECT n=3 FROM triggers)
  AND (SELECT n=4 FROM indexes)
  AND EXISTS(SELECT FROM installed WHERE prosecdef AND provolatile='v'
    AND proconfig @> ARRAY['search_path=public','statement_timeout=120s','lock_timeout=0']
    AND has_function_privilege('service_role',oid,'EXECUTE')
    AND NOT has_function_privilege('anon',oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',oid,'EXECUTE'))
  AND md5(pg_get_functiondef(to_regprocedure('public.rebuild_style_groups_batch(uuid,integer)')))='65c89b152f1d4aa49f3877043a16bd6b'
  AND md5(pg_get_functiondef(to_regprocedure('public.clear_style_group_batch(uuid,integer)')))='3dbea0ab37aa21181efa966cbb4e1d8f'
  AND NOT EXISTS(SELECT FROM (VALUES
    ('public.stamp_style_group_asset_change()'),
    ('public.stamp_style_group_definition_change()'),
    ('public.touch_style_group_tag_change()')
  ) e(signature) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
    WHERE p.oid IS NULL OR NOT p.prosecdef OR p.provolatile<>'v'
      OR NOT coalesce(p.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=public, pg_temp']
      OR has_function_privilege('anon',p.oid,'EXECUTE')
      OR has_function_privilege('authenticated',p.oid,'EXECUTE'))
  AND EXISTS(SELECT FROM pg_proc p WHERE p.oid=to_regprocedure('public.queue_nightly_rebuild_style_groups()')
    AND p.prosecdef AND p.provolatile='v' AND p.proconfig @> ARRAY['search_path=public']
    AND has_function_privilege('service_role',p.oid,'EXECUTE')
    AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
    AND pg_get_functiondef(p.oid) LIKE '%pg_advisory_xact_lock(hashtext(''BULK_OPERATIONS''))%'
    AND pg_get_functiondef(p.oid) LIKE '%last_successful_cutoff%')
) as passed
