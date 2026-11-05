-- Work issue #5639; application need u2giants/popdam3#469.
-- derived-from: 20260911210844, 20260710135700
-- Share the existing matching bodies through private overloads. Existing full
-- callers keep their zero-argument entry points. No row is rewritten on apply.
-- Global catalog/evidence reads are retained; only bridge write candidates scope.

CREATE OR REPLACE FUNCTION plm.refresh_style_tracker_item_bridge(p_row_ids uuid[])
 RETURNS TABLE(inserted_count integer, updated_count integer, total_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'plm', 'core', 'extensions'
AS $function$
DECLARE
  v_before integer;
  v_after integer;
BEGIN
  IF p_row_ids IS NULL THEN
    SELECT count(*) INTO v_before FROM plm.style_tracker_item_bridge;
  END IF;

  WITH erp_matches AS (
    SELECT upper(trim(style_number)) AS normalized_sku, CASE WHEN count(*) = 1 THEN min(id::text)::uuid END AS id, count(*) AS candidate_count
    FROM plm.legacy_erp_item_identity
    WHERE style_number IS NOT NULL AND trim(style_number) <> ''
    GROUP BY upper(trim(style_number))
  ),
  style_group_matches AS (
    SELECT upper(trim(sku)) AS normalized_sku, min(id::text)::uuid AS id, count(*) AS candidate_count
    FROM public.style_groups
    WHERE sku IS NOT NULL AND trim(sku) <> ''
    GROUP BY upper(trim(sku))
  ),
  company_matches AS (
    SELECT lower(regexp_replace(trim(name), '\s+', ' ', 'g')) AS normalized_name, min(id::text)::uuid AS id, count(*) AS candidate_count
    FROM core.customer
    WHERE name IS NOT NULL AND trim(name) <> ''
    GROUP BY lower(regexp_replace(trim(name), '\s+', ' ', 'g'))
  ),
  public_licensor_matches AS (
    SELECT lower(regexp_replace(trim(name), '\s+', ' ', 'g')) AS normalized_name, min(id::text)::uuid AS id, count(*) AS candidate_count
    FROM public.licensors
    WHERE name IS NOT NULL AND trim(name) <> ''
    GROUP BY lower(regexp_replace(trim(name), '\s+', ' ', 'g'))
  ),
  core_licensor_matches AS (
    SELECT lower(regexp_replace(trim(name), '\s+', ' ', 'g')) AS normalized_name, min(id::text)::uuid AS id, count(*) AS candidate_count
    FROM core.licensor
    WHERE name IS NOT NULL AND trim(name) <> ''
    GROUP BY lower(regexp_replace(trim(name), '\s+', ' ', 'g'))
  ),
  factory_matches AS (
    SELECT lower(regexp_replace(trim(name), '\s+', ' ', 'g')) AS normalized_name, min(id::text)::uuid AS id, count(*) AS candidate_count
    FROM core.factory
    WHERE name IS NOT NULL AND trim(name) <> ''
    GROUP BY lower(regexp_replace(trim(name), '\s+', ' ', 'g'))
  ),
  plm_item_matches AS (
    SELECT upper(trim(coalesce(style_number, item_number))) AS normalized_sku, CASE WHEN count(*) = 1 THEN min(id::text)::uuid END AS id, count(*) AS candidate_count
    FROM plm.item
    WHERE coalesce(style_number, item_number) IS NOT NULL AND trim(coalesce(style_number, item_number)) <> ''
    GROUP BY upper(trim(coalesce(style_number, item_number)))
  ),
  row_source AS (
    -- Separate branches keep bounded mode eligible for the primary-key index,
    -- including a cached generic plan; NULL retains the original full caller.
    SELECT r.* FROM public.style_tracker_rows r
    WHERE p_row_ids IS NULL AND r.source_sheet IN ('License.Style', 'Generic.Style')
    UNION ALL
    SELECT r.* FROM public.style_tracker_rows r
    WHERE p_row_ids IS NOT NULL AND r.id = ANY(p_row_ids)
      AND r.source_sheet IN ('License.Style', 'Generic.Style')
  ),
  row_values AS (
    SELECT
      r.*,
      plm.normalize_style_tracker_value('sku', r.sku) AS sku_norm,
      plm.normalize_style_tracker_value('customer', r.customer) AS customer_norm,
      plm.normalize_style_tracker_value('licensor', r.licensor) AS licensor_norm,
      plm.normalize_style_tracker_value('factory', r.default_vendor) AS factory_norm
    FROM row_source r
  ),
  fuzzy_source_values AS (
    -- Full mode retains the original source. Bounded mode reads only the
    -- narrow evidence columns globally, never every complete Styles row.
    SELECT customer, licensor, default_vendor, customer_norm, licensor_norm, factory_norm
    FROM row_values WHERE p_row_ids IS NULL
    UNION ALL
    SELECT r.customer, r.licensor, r.default_vendor,
      plm.normalize_style_tracker_value('customer', r.customer),
      plm.normalize_style_tracker_value('licensor', r.licensor),
      plm.normalize_style_tracker_value('factory', r.default_vendor)
    FROM public.style_tracker_rows r
    WHERE p_row_ids IS NOT NULL AND r.source_sheet IN ('License.Style', 'Generic.Style')
  ),
  customer_values AS (
    SELECT DISTINCT customer_norm, customer
    FROM fuzzy_source_values
    WHERE customer_norm IS NOT NULL
      AND (p_row_ids IS NULL OR customer_norm IN (SELECT customer_norm FROM row_values))
  ),
  licensor_values AS (
    SELECT DISTINCT licensor_norm, licensor
    FROM fuzzy_source_values
    WHERE licensor_norm IS NOT NULL
      AND (p_row_ids IS NULL OR licensor_norm IN (SELECT licensor_norm FROM row_values))
  ),
  factory_values AS (
    SELECT DISTINCT factory_norm, default_vendor
    FROM fuzzy_source_values
    WHERE factory_norm IS NOT NULL
      AND (p_row_ids IS NULL OR factory_norm IN (SELECT factory_norm FROM row_values))
  ),
  fuzzy_customers AS (
    SELECT DISTINCT ON (v.customer_norm)
      v.customer_norm,
      jsonb_build_object('target_schema', c.target_schema, 'target_table', c.target_table, 'target_id', c.target_id, 'target_label', c.target_label, 'score', c.score) AS suggestion
    FROM customer_values v
    CROSS JOIN LATERAL public.search_style_tracker_link_candidates('customer', v.customer, 1) c
    ORDER BY v.customer_norm, c.score DESC
  ),
  fuzzy_licensors AS (
    SELECT DISTINCT ON (v.licensor_norm)
      v.licensor_norm,
      jsonb_build_object('target_schema', c.target_schema, 'target_table', c.target_table, 'target_id', c.target_id, 'target_label', c.target_label, 'score', c.score) AS suggestion
    FROM licensor_values v
    CROSS JOIN LATERAL public.search_style_tracker_link_candidates('licensor', v.licensor, 1) c
    ORDER BY v.licensor_norm, c.score DESC
  ),
  fuzzy_factories AS (
    SELECT DISTINCT ON (v.factory_norm)
      v.factory_norm,
      jsonb_build_object('target_schema', c.target_schema, 'target_table', c.target_table, 'target_id', c.target_id, 'target_label', c.target_label, 'score', c.score) AS suggestion
    FROM factory_values v
    CROSS JOIN LATERAL public.search_style_tracker_link_candidates('factory', v.default_vendor, 1) c
    ORDER BY v.factory_norm, c.score DESC
  ),
  resolved AS (
    SELECT
      r.*,
      CASE WHEN sku_res.resolution_type = 'canonical' AND sku_res.target_schema = 'public' AND sku_res.target_table = 'erp_items_current' THEN sku_res.target_id ELSE erp.id END AS erp_item_id,
      CASE WHEN sku_res.resolution_type = 'canonical' AND sku_res.target_schema = 'public' AND sku_res.target_table = 'style_groups' THEN sku_res.target_id ELSE sg.id END AS style_group_id,
      CASE WHEN customer_res.resolution_type = 'canonical' AND customer_res.target_schema = 'core' AND customer_res.target_table = 'customer' THEN customer_res.target_id ELSE company.id END AS company_id,
      CASE WHEN licensor_res.resolution_type = 'canonical' AND licensor_res.target_schema = 'public' AND licensor_res.target_table = 'licensors' THEN licensor_res.target_id ELSE public_lic.id END AS public_licensor_id,
      CASE WHEN licensor_res.resolution_type = 'canonical' AND licensor_res.target_schema = 'core' AND licensor_res.target_table = 'licensor' THEN licensor_res.target_id ELSE core_lic.id END AS core_licensor_id,
      CASE WHEN factory_res.resolution_type = 'canonical' AND factory_res.target_schema = 'core' AND factory_res.target_table = 'factory' THEN factory_res.target_id ELSE factory.id END AS factory_id,
      CASE WHEN sku_res.resolution_type = 'canonical' AND sku_res.target_schema = 'plm' AND sku_res.target_table = 'item' THEN sku_res.target_id ELSE coalesce(plm_item.id, content_item.id) END AS plm_item_id,
      sku_res.local_value AS local_sku_value,
      customer_res.local_value AS local_customer_value,
      licensor_res.local_value AS local_licensor_value,
      factory_res.local_value AS local_factory_value,
      coalesce(erp.candidate_count, 0) AS erp_candidates,
      coalesce(sg.candidate_count, 0) AS style_group_candidates,
      coalesce(company.candidate_count, 0) AS company_candidates,
      coalesce(public_lic.candidate_count, 0) AS public_licensor_candidates,
      coalesce(core_lic.candidate_count, 0) AS core_licensor_candidates,
      coalesce(factory.candidate_count, 0) AS factory_candidates,
      coalesce(nullif(content_item.candidate_count, 0), plm_item.candidate_count, 0) AS plm_item_candidates,
      fuzzy_customer.suggestion AS fuzzy_customer_suggestion,
      fuzzy_licensor.suggestion AS fuzzy_licensor_suggestion,
      fuzzy_factory.suggestion AS fuzzy_factory_suggestion
    FROM row_values r
    LEFT JOIN erp_matches erp ON erp.normalized_sku = r.sku_norm
    LEFT JOIN style_group_matches sg ON sg.normalized_sku = r.sku_norm
    LEFT JOIN company_matches company ON company.normalized_name = r.customer_norm
    LEFT JOIN public_licensor_matches public_lic ON public_lic.normalized_name = r.licensor_norm
    LEFT JOIN core_licensor_matches core_lic ON core_lic.normalized_name = r.licensor_norm
    LEFT JOIN factory_matches factory ON factory.normalized_name = r.factory_norm
    LEFT JOIN plm_item_matches plm_item ON plm_item.normalized_sku = r.sku_norm
    LEFT JOIN plm.style_tracker_item_bridge existing_bridge ON existing_bridge.style_tracker_row_id = r.id
    LEFT JOIN plm.legacy_erp_item_identity existing_erp ON existing_erp.id = existing_bridge.erp_item_id
    LEFT JOIN LATERAL (
      WITH scored AS (
        SELECT p.id,
          ((nullif(trim(existing_erp.item_description), '') is not null and upper(trim(existing_erp.item_description)) = upper(trim(p.description)))::int +
           (nullif(trim(existing_erp.mg01_code), '') is not null and upper(trim(existing_erp.mg01_code)) = upper(trim(p.raw ->> 'merchGroup01')))::int +
           (nullif(trim(existing_erp.mg02_code), '') is not null and upper(trim(existing_erp.mg02_code)) = upper(trim(p.raw ->> 'merchGroup02')))::int +
           (nullif(trim(existing_erp.mg03_code), '') is not null and upper(trim(existing_erp.mg03_code)) = upper(trim(p.raw ->> 'merchGroup03')))::int +
           (nullif(trim(existing_erp.mg04_code), '') is not null and upper(trim(existing_erp.mg04_code)) = upper(trim(p.raw ->> 'merchGroup04')))::int +
           (nullif(trim(existing_erp.mg05_code), '') is not null and upper(trim(existing_erp.mg05_code)) = upper(trim(p.raw ->> 'merchGroup05')))::int +
           (nullif(trim(existing_erp.mg06_code), '') is not null and upper(trim(existing_erp.mg06_code)) = upper(trim(p.raw ->> 'merchGroup06')))::int) AS score
        FROM plm.item p
        WHERE existing_erp.id is not null
          AND upper(trim(p.item_number)) = upper(trim(existing_erp.external_id))
      ), ranked AS (
        SELECT id, score, dense_rank() over (order by score desc) AS score_rank
        FROM scored
      )
      SELECT CASE WHEN count(*) = 1 AND max(score) > 0 THEN min(id::text)::uuid END AS id,
             CASE WHEN max(score) > 0 THEN count(*)::bigint ELSE 0::bigint END AS candidate_count
      FROM ranked
      WHERE score_rank = 1
    ) content_item ON plm_item.candidate_count > 1
    LEFT JOIN plm.style_tracker_value_resolution sku_res ON sku_res.field_key = 'sku' AND sku_res.normalized_value = r.sku_norm
    LEFT JOIN plm.style_tracker_value_resolution customer_res ON customer_res.field_key = 'customer' AND customer_res.normalized_value = r.customer_norm
    LEFT JOIN plm.style_tracker_value_resolution licensor_res ON licensor_res.field_key = 'licensor' AND licensor_res.normalized_value = r.licensor_norm
    LEFT JOIN plm.style_tracker_value_resolution factory_res ON factory_res.field_key = 'factory' AND factory_res.normalized_value = r.factory_norm
    LEFT JOIN fuzzy_customers fuzzy_customer ON fuzzy_customer.customer_norm = r.customer_norm AND company.id IS NULL AND customer_res.id IS NULL
    LEFT JOIN fuzzy_licensors fuzzy_licensor ON fuzzy_licensor.licensor_norm = r.licensor_norm AND public_lic.id IS NULL AND core_lic.id IS NULL AND licensor_res.id IS NULL
    LEFT JOIN fuzzy_factories fuzzy_factory ON fuzzy_factory.factory_norm = r.factory_norm AND factory.id IS NULL AND factory_res.id IS NULL
  ),
  upserted AS (
    INSERT INTO plm.style_tracker_item_bridge (
      style_tracker_row_id,
      source_workbook_id,
      source_sheet,
      source_row_number,
      tracker_type,
      sku,
      description,
      customer_name,
      designer_name,
      commissioned,
      upc,
      customer_sku,
      licensor_name,
      license_status,
      royalty,
      concept_status,
      pre_production_status,
      production_status,
      default_vendor_name,
      discontinued,
      notes,
      erp_item_id,
      style_group_id,
      company_id,
      public_licensor_id,
      core_licensor_id,
      factory_id,
      plm_item_id,
      match_status,
      match_confidence,
      match_notes,
      raw_row_data,
      last_matched_at
    )
    SELECT
      id,
      source_workbook_id,
      source_sheet,
      source_row_number,
      tracker_type,
      sku,
      description,
      customer,
      designer,
      commissioned,
      upc,
      customer_sku,
      licensor,
      license_status,
      royalty,
      concept_status,
      pre_production_status,
      production_status,
      default_vendor,
      discontinued,
      notes,
      erp_item_id,
      style_group_id,
      company_id,
      public_licensor_id,
      core_licensor_id,
      factory_id,
      plm_item_id,
      CASE
        WHEN greatest(erp_candidates, style_group_candidates, company_candidates, public_licensor_candidates, core_licensor_candidates, factory_candidates, plm_item_candidates) > 1
          THEN 'needs_review'
        WHEN fuzzy_customer_suggestion IS NOT NULL OR fuzzy_licensor_suggestion IS NOT NULL OR fuzzy_factory_suggestion IS NOT NULL
          THEN 'needs_review'
        WHEN erp_item_id IS NOT NULL OR style_group_id IS NOT NULL OR company_id IS NOT NULL OR public_licensor_id IS NOT NULL OR core_licensor_id IS NOT NULL OR factory_id IS NOT NULL OR plm_item_id IS NOT NULL
          THEN CASE WHEN erp_item_id IS NOT NULL OR style_group_id IS NOT NULL OR plm_item_id IS NOT NULL THEN 'matched' ELSE 'partial' END
        WHEN local_sku_value IS NOT NULL OR local_customer_value IS NOT NULL OR local_licensor_value IS NOT NULL OR local_factory_value IS NOT NULL
          THEN 'partial'
        ELSE 'unmatched'
      END,
      CASE
        WHEN greatest(erp_candidates, style_group_candidates, company_candidates, public_licensor_candidates, core_licensor_candidates, factory_candidates, plm_item_candidates) > 1
          THEN 'conflict'
        WHEN fuzzy_customer_suggestion IS NOT NULL OR fuzzy_licensor_suggestion IS NOT NULL OR fuzzy_factory_suggestion IS NOT NULL
          THEN 'possible'
        WHEN erp_item_id IS NOT NULL OR style_group_id IS NOT NULL OR plm_item_id IS NOT NULL
          THEN 'probable'
        WHEN company_id IS NOT NULL OR public_licensor_id IS NOT NULL OR core_licensor_id IS NOT NULL OR factory_id IS NOT NULL
          THEN 'possible'
        ELSE 'possible'
      END,
      jsonb_strip_nulls(jsonb_build_object(
        'erp_candidates', erp_candidates,
        'style_group_candidates', style_group_candidates,
        'company_candidates', company_candidates,
        'public_licensor_candidates', public_licensor_candidates,
        'core_licensor_candidates', core_licensor_candidates,
        'factory_candidates', factory_candidates,
        'plm_item_candidates', plm_item_candidates,
        'fuzzy', jsonb_strip_nulls(jsonb_build_object(
          'customer', fuzzy_customer_suggestion,
          'licensor', fuzzy_licensor_suggestion,
          'factory', fuzzy_factory_suggestion
        )),
        'master_data_values', jsonb_strip_nulls(jsonb_build_object(
          'sku', local_sku_value,
          'customer', local_customer_value,
          'licensor', local_licensor_value,
          'factory', local_factory_value
        ))
      )),
      row_data,
      now()
    FROM resolved
    WHERE p_row_ids IS NULL OR id = ANY(p_row_ids)
    ON CONFLICT (style_tracker_row_id) DO UPDATE SET
      source_workbook_id = EXCLUDED.source_workbook_id,
      source_sheet = EXCLUDED.source_sheet,
      source_row_number = EXCLUDED.source_row_number,
      tracker_type = EXCLUDED.tracker_type,
      sku = EXCLUDED.sku,
      description = EXCLUDED.description,
      customer_name = EXCLUDED.customer_name,
      designer_name = EXCLUDED.designer_name,
      commissioned = EXCLUDED.commissioned,
      upc = EXCLUDED.upc,
      customer_sku = EXCLUDED.customer_sku,
      licensor_name = EXCLUDED.licensor_name,
      license_status = EXCLUDED.license_status,
      royalty = EXCLUDED.royalty,
      concept_status = EXCLUDED.concept_status,
      pre_production_status = EXCLUDED.pre_production_status,
      production_status = EXCLUDED.production_status,
      default_vendor_name = EXCLUDED.default_vendor_name,
      discontinued = EXCLUDED.discontinued,
      notes = EXCLUDED.notes,
      erp_item_id = coalesce(plm.style_tracker_item_bridge.erp_item_id, EXCLUDED.erp_item_id),
      style_group_id = EXCLUDED.style_group_id,
      company_id = EXCLUDED.company_id,
      public_licensor_id = EXCLUDED.public_licensor_id,
      core_licensor_id = EXCLUDED.core_licensor_id,
      factory_id = EXCLUDED.factory_id,
      plm_item_id = coalesce(plm.style_tracker_item_bridge.plm_item_id, EXCLUDED.plm_item_id),
      match_status = EXCLUDED.match_status,
      match_confidence = EXCLUDED.match_confidence,
      match_notes = EXCLUDED.match_notes,
      raw_row_data = EXCLUDED.raw_row_data,
      last_matched_at = EXCLUDED.last_matched_at
    RETURNING (xmax = 0)::integer AS inserted_flag
  )
  SELECT
    coalesce(sum(inserted_flag), 0)::integer,
    (count(*) - coalesce(sum(inserted_flag), 0))::integer,
    count(*)::integer
  INTO inserted_count, updated_count, total_count
  FROM upserted;

  IF p_row_ids IS NULL THEN
    -- Preserve legacy full-refresh accounting only for that original mode.
    SELECT count(*) INTO v_after FROM plm.style_tracker_item_bridge;
    inserted_count := greatest(v_after - v_before, 0);
  END IF;

  RETURN NEXT;
END;
$function$;

CREATE OR REPLACE FUNCTION plm.apply_style_tracker_designer_resolutions(p_row_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'plm', 'core'
AS $function$
declare
  v_updated integer;
begin
  with row_values as (
    select
      b.id as bridge_id,
      lower(regexp_replace(btrim(r.designer), '\s+', ' ', 'g')) as designer_norm
    from plm.style_tracker_item_bridge b
    join public.style_tracker_rows r on r.id = b.style_tracker_row_id
    where nullif(btrim(r.designer), '') is not null
  ),
  unique_first_names as (
    select split_part(normalized_name, ' ', 1) as first_name
    from core.creative_designer
    where status = 'active'
    group by split_part(normalized_name, ' ', 1)
    having count(*) = 1
  ),
  automatic_matches as (
    select distinct on (rv.bridge_id)
      rv.bridge_id,
      cd.id,
      cd.name
    from row_values rv
    join core.creative_designer cd
      on cd.status = 'active'
     and (
       cd.normalized_name = rv.designer_norm
       or (
         rv.designer_norm = split_part(cd.normalized_name, ' ', 1)
         and exists (
           select 1
           from unique_first_names u
           where u.first_name = rv.designer_norm
         )
       )
     )
    order by rv.bridge_id, cd.name
  ),
  resolved as (
    select
      rv.bridge_id,
      res.resolution_type,
      res.target_schema,
      res.target_table,
      res.target_id,
      res.target_label,
      res.local_value,
      case
        when res.resolution_type = 'canonical'
          and res.target_schema = 'core'
          and res.target_table = 'creative_designer'
          then res.target_id
        when res.id is null then am.id
        else null
      end as creative_designer_id,
      case
        when res.resolution_type = 'canonical'
          and res.target_schema = 'core'
          and res.target_table = 'creative_designer'
          then res.target_label
        when res.id is null then am.name
        else null
      end as creative_designer_name
    from row_values rv
    left join plm.style_tracker_value_resolution res
      on res.field_key = 'designer'
     and res.normalized_value = rv.designer_norm
    left join automatic_matches am
      on am.bridge_id = rv.bridge_id
  )
  update plm.style_tracker_item_bridge b
  set
    creative_designer_id = resolved.creative_designer_id,
    match_notes = case
      when resolved.resolution_type is null then
        case
          when b.match_notes->'manual_resolution'->>'field_key' = 'designer'
            then (coalesce(b.match_notes, '{}'::jsonb) - 'manual_resolution') #- '{manual_resolutions,designer}'
          else coalesce(b.match_notes, '{}'::jsonb) #- '{manual_resolutions,designer}'
        end
      else
        jsonb_set(
          jsonb_set(
            jsonb_set(
              coalesce(b.match_notes, '{}'::jsonb),
              '{manual_resolutions}',
              coalesce(b.match_notes->'manual_resolutions', '{}'::jsonb),
              true
            ),
            '{manual_resolutions,designer}',
            jsonb_strip_nulls(jsonb_build_object(
              'field_key', 'designer',
              'resolution_type', resolved.resolution_type,
              'target_schema', resolved.target_schema,
              'target_table', resolved.target_table,
              'target_id', resolved.target_id,
              'target_label', resolved.target_label,
              'local_value', resolved.local_value
            )),
            true
          ),
          '{manual_resolution}',
          jsonb_strip_nulls(jsonb_build_object(
            'field_key', 'designer',
            'resolution_type', resolved.resolution_type,
            'target_schema', resolved.target_schema,
            'target_table', resolved.target_table,
            'target_id', resolved.target_id,
            'target_label', resolved.target_label,
            'local_value', resolved.local_value
          )),
          true
        )
    end,
    match_status = case
      when resolved.creative_designer_id is not null and b.match_status = 'unmatched' then 'partial'
      when resolved.resolution_type = 'master_data' and b.match_status = 'unmatched' then 'partial'
      else b.match_status
    end,
    match_confidence = case
      when resolved.creative_designer_id is not null and b.match_confidence = 'possible' then 'verified'
      when resolved.resolution_type = 'master_data' and b.match_confidence = 'possible' then 'verified'
      else b.match_confidence
    end,
    last_matched_at = case
      when b.creative_designer_id is distinct from resolved.creative_designer_id then now()
      else b.last_matched_at
    end
  from resolved
  where b.id = resolved.bridge_id
    and (p_row_ids is null or b.style_tracker_row_id = any(p_row_ids))
    and (
      b.creative_designer_id is distinct from resolved.creative_designer_id
      or (
        resolved.resolution_type is not null
        and coalesce(b.match_notes->'manual_resolutions'->'designer', '{}'::jsonb) is distinct from jsonb_strip_nulls(jsonb_build_object(
          'field_key', 'designer',
          'resolution_type', resolved.resolution_type,
          'target_schema', resolved.target_schema,
          'target_table', resolved.target_table,
          'target_id', resolved.target_id,
          'target_label', resolved.target_label,
          'local_value', resolved.local_value
        ))
      )
    );

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$function$;

-- Keep existing identity/grants and full-refresh behavior for all current callers.
create or replace function plm.refresh_style_tracker_item_bridge()
returns table(inserted_count integer, updated_count integer, total_count integer)
language sql security definer set search_path = ''
as $$ select * from plm.refresh_style_tracker_item_bridge(null::uuid[]); $$;

create or replace function plm.apply_style_tracker_designer_resolutions()
returns integer language sql security definer set search_path = ''
as $$ select plm.apply_style_tracker_designer_resolutions(null::uuid[]); $$;

-- NULL/full mode is private to the existing definer wrappers.
revoke all on function plm.refresh_style_tracker_item_bridge(uuid[]) from public, anon, authenticated, service_role;
revoke all on function plm.apply_style_tracker_designer_resolutions(uuid[]) from public, anon, authenticated, service_role;

create or replace function public.refresh_style_tracker_item_bridge_rows(p_row_ids uuid[])
returns table(inserted_count integer, updated_count integer, total_count integer)
language plpgsql security definer set search_path = ''
as $bounded$
declare
  v_result record;
  v_designer_updated integer;
begin
  -- Settled Master Data access: every signed-in POP user may edit Styles.
  -- Match that access; do not introduce a designer/admin/DAM-role restriction.
  if auth.uid() is null then
    raise exception 'Styles access requires a signed-in user' using errcode = '42501';
  end if;
  if p_row_ids is null or cardinality(p_row_ids) = 0
     or cardinality(p_row_ids) > 25 or array_ndims(p_row_ids) <> 1 then
    raise exception 'Provide one to 25 distinct non-null Styles row IDs' using errcode = '22023';
  end if;
  if array_position(p_row_ids, null) is not null
     or cardinality(p_row_ids) <> (select count(distinct id) from unnest(p_row_ids) as ids(id)) then
    raise exception 'Provide one to 25 distinct non-null Styles row IDs' using errcode = '22023';
  end if;
  select * into v_result from plm.refresh_style_tracker_item_bridge(p_row_ids);
  v_designer_updated := plm.apply_style_tracker_designer_resolutions(p_row_ids);
  inserted_count := v_result.inserted_count;
  updated_count := v_result.updated_count + v_designer_updated;
  total_count := v_result.total_count;
  return next;
end;
$bounded$;
revoke all on function public.refresh_style_tracker_item_bridge_rows(uuid[]) from public, anon;
grant execute on function public.refresh_style_tracker_item_bridge_rows(uuid[]) to authenticated;
comment on function public.refresh_style_tracker_item_bridge_rows(uuid[]) is
  'Refresh one to 25 exact Styles rows and their bridge designer resolution; preserve every other bridge row. Full refresh callers retain the zero-argument RPC.';
