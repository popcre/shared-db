-- #5662 / PopDAM #680, #706. Preserve visited-count and search catch-up contracts.
-- Only redundant style_groups writes are removed; downstream refresh cost is unchanged.
CREATE OR REPLACE FUNCTION public.refresh_style_group_primaries(p_group_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '30s'
SET lock_timeout TO '0'
AS $function$
DECLARE
  v_visited integer;
  v_unchanged uuid[];
  v_group_id uuid;
BEGIN
  WITH picked AS MATERIALIZED (
    SELECT DISTINCT ON (sg.id)
      sg.id AS style_group_id,
      a.id AS primary_asset_id,
      a.asset_type::text AS primary_asset_type,
      a.thumbnail_url AS primary_thumbnail_url,
      a.thumbnail_error AS primary_thumbnail_error
    FROM public.style_groups sg
    LEFT JOIN public.assets a
      ON a.style_group_id = sg.id AND a.is_deleted = false
    WHERE sg.id = ANY(p_group_ids)
    ORDER BY sg.id, a.primary_sort_tier ASC, a.created_at ASC
  ), classified AS MATERIALIZED (
    SELECT picked.*,
      ROW(sg.primary_asset_id, sg.primary_asset_type,
          sg.primary_thumbnail_url, sg.primary_thumbnail_error)
      IS DISTINCT FROM
      ROW(picked.primary_asset_id, picked.primary_asset_type,
          picked.primary_thumbnail_url, picked.primary_thumbnail_error) AS changed
    FROM picked
    JOIN public.style_groups sg ON sg.id = picked.style_group_id
  ), updated AS (
    UPDATE public.style_groups sg SET
      primary_asset_id = picked.primary_asset_id,
      primary_asset_type = picked.primary_asset_type,
      primary_thumbnail_url = picked.primary_thumbnail_url,
      primary_thumbnail_error = picked.primary_thumbnail_error,
      updated_at = now()
    FROM classified picked
    WHERE sg.id = picked.style_group_id AND picked.changed
    RETURNING sg.id
  )
  SELECT count(*)::integer,
         array_agg(style_group_id ORDER BY style_group_id) FILTER (WHERE NOT changed)
  INTO v_visited, v_unchanged
  FROM classified;

  -- Changed rows retain their existing AFTER UPDATE search refresh. Unchanged
  -- rows still need nightly catch-up, e.g. a character master-name correction
  -- has no association-row event. Refresh each such group exactly once.
  FOREACH v_group_id IN ARRAY coalesce(v_unchanged, ARRAY[]::uuid[])
  LOOP
    PERFORM public.refresh_dam_search_style_group_document(v_group_id);
  END LOOP;

  -- Existing callers count visited groups, not physically changed rows.
  RETURN v_visited;
END;
$function$;
