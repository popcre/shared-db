-- #5447 / backend #278. Private typed evidence, never a product classification.
-- The canonical parent marker is item_detail.pre_pack_code, not component linkage.
-- Completeness is tied to the recorded canonical snapshot; as-of age remains explicit.
SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '8s';

DO $guard$
BEGIN
  IF current_user<>'postgres' THEN
    RAISE EXCEPTION 'REFUSED: projection migration must use exact native postgres actor';
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname='designflow_hts_prepack_projection_owner') THEN
    RAISE EXCEPTION 'REFUSED: projection owner already exists; unexpected authority is not reusable';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='designflow_hts_evaluation_read') THEN
    RAISE EXCEPTION 'REFUSED: evaluation access prerequisite absent';
  END IF;
  IF EXISTS (SELECT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
             WHERE (n.nspname,c.relname) IN (('plm','item'),('coldlion','item_detail'),('coldlion','sync_run'))
               AND NOT c.relrowsecurity)
     OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
         WHERE (n.nspname,c.relname) IN (('plm','item'),('coldlion','item_detail'),('coldlion','sync_run'))) <> 3 THEN
    RAISE EXCEPTION 'REFUSED: exact RLS-enabled source relations required';
  END IF;
END
$guard$;

CREATE ROLE designflow_hts_prepack_projection_owner NOLOGIN NOINHERIT NOSUPERUSER
  NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE ON SCHEMA plm,coldlion TO designflow_hts_prepack_projection_owner;
GRANT SELECT (item_number,raw) ON plm.item TO designflow_hts_prepack_projection_owner;
GRANT SELECT (item_no,company_code,division_code,pre_pack_code,run_id,fetched_at,last_seen_at)
  ON coldlion.item_detail TO designflow_hts_prepack_projection_owner;
GRANT SELECT (id,endpoint,company_code,division_code,request_params,status,started_at,finished_at,requested_by)
  ON coldlion.sync_run TO designflow_hts_prepack_projection_owner;
CREATE POLICY hts_prepack_projection_owner_select ON coldlion.sync_run
  FOR SELECT TO designflow_hts_prepack_projection_owner USING (endpoint='/itemDetails');
CREATE POLICY hts_prepack_projection_owner_source_guard ON coldlion.sync_run AS RESTRICTIVE
  FOR SELECT TO designflow_hts_prepack_projection_owner USING (endpoint='/itemDetails');
CREATE POLICY hts_prepack_projection_owner_select ON plm.item
  FOR SELECT TO designflow_hts_prepack_projection_owner USING (source_system='coldlion');
-- Existing PUBLIC permissive policies must never broaden this owner's source scope.
CREATE POLICY hts_prepack_projection_owner_source_guard ON plm.item AS RESTRICTIVE
  FOR SELECT TO designflow_hts_prepack_projection_owner USING (source_system='coldlion');
CREATE POLICY hts_prepack_projection_owner_select ON coldlion.item_detail
  FOR SELECT TO designflow_hts_prepack_projection_owner USING (true);

-- PG17 gives a constrained CREATEROLE actor admin-only, non-SET membership.
-- Preserve that exact initial graph (including a superuser's absent membership).
DO $bootstrap$
DECLARE original jsonb;
BEGIN
  SELECT jsonb_build_object('grantor',m.grantor::text,'admin',m.admin_option,'inherit',m.inherit_option,'set',m.set_option)
    INTO original FROM pg_auth_members m
    WHERE m.roleid='designflow_hts_prepack_projection_owner'::regrole
      AND m.member=current_user::regrole;
  IF original IS NOT NULL AND (original->>'admin'<>'true' OR original->>'inherit'<>'false' OR original->>'set'<>'false' OR original->>'grantor'=current_user::regrole::oid::text) THEN
    RAISE EXCEPTION 'REFUSED: unexpected new-owner bootstrap membership';
  END IF;
  PERFORM set_config('hts.prepack_original_membership',coalesce(original::text,'null'),true);
END
$bootstrap$;
GRANT designflow_hts_prepack_projection_owner TO postgres WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
GRANT CREATE ON SCHEMA plm TO designflow_hts_prepack_projection_owner;

CREATE VIEW plm.hts_evaluation_prepack_membership
WITH (security_barrier=true,security_invoker=false) AS
WITH contexts AS (
  SELECT DISTINCT upper(btrim(i.item_number)) AS style_number,
    i.item_number AS source_item_number,
    nullif(i.raw->>'companyCode','') AS company_code,
    nullif(i.raw->>'divisionCode','') AS division_code
  FROM plm.item i
)
SELECT c.style_number,c.company_code,c.division_code,
  d.matched_count AS detail_matched_count,
  CASE WHEN proof.scope_complete AND d.current_parent_count>0 THEN 'prepack'
       WHEN proof.scope_complete AND d.matched_count>0 AND d.rows_covered THEN 'non_prepack'
       ELSE 'unknown' END::text AS state,
  statement_timestamp() AS observed_at,
  (proof.scope_complete AND d.matched_count>0 AND d.rows_covered) AS source_complete,
  snapshot.finished_at AS source_as_of
FROM contexts c
LEFT JOIN LATERAL (
  SELECT r.id,r.finished_at,r.started_at,r.requested_by,r.request_params,r.division_code
  FROM coldlion.sync_run r
  WHERE r.endpoint='/itemDetails' AND r.company_code=c.company_code
    AND r.status='succeeded' AND r.request_params @> '{"fullSnapshot":true}'::jsonb
  ORDER BY r.finished_at DESC NULLS LAST,r.started_at DESC,r.id DESC LIMIT 1
) snapshot ON true
CROSS JOIN LATERAL (
  SELECT count(*)::integer AS matched_count,
    count(*) FILTER (WHERE nullif(btrim(detail.pre_pack_code),'') IS NOT NULL
      AND coalesce(detail.run_id=snapshot.id AND detail.fetched_at=snapshot.finished_at
        AND detail.last_seen_at=snapshot.finished_at,false))::integer AS current_parent_count,
    coalesce(bool_and(coalesce(detail.run_id=snapshot.id AND detail.fetched_at=snapshot.finished_at
      AND detail.last_seen_at=snapshot.finished_at,false)),false) AS rows_covered
  FROM coldlion.item_detail detail
  WHERE detail.company_code=c.company_code AND detail.division_code=c.division_code
    AND detail.item_no=c.source_item_number
) d
CROSS JOIN LATERAL (
  SELECT coalesce(
    nullif(btrim(c.company_code),'') IS NOT NULL AND nullif(btrim(c.division_code),'') IS NOT NULL
    AND c.division_code<>'EP001'
    AND snapshot.id IS NOT NULL AND snapshot.finished_at IS NOT NULL
    AND snapshot.requested_by='coldlion-landing sync-masters'
    AND (snapshot.division_code IS NULL OR snapshot.division_code=c.division_code)
    AND snapshot.request_params->>'companyCode'=c.company_code
    AND snapshot.request_params - ARRAY['companyCode','fullSnapshot','requests','orphanedWithoutItemHeader']::text[]='{}'::jsonb
    AND EXISTS (SELECT FROM jsonb_array_elements(CASE
      WHEN jsonb_typeof(snapshot.request_params->'requests')='array' THEN snapshot.request_params->'requests'
      ELSE '[]'::jsonb END) request
      WHERE request = jsonb_build_object('companyCode',c.company_code))
    AND EXISTS (SELECT FROM jsonb_array_elements(CASE
      WHEN jsonb_typeof(snapshot.request_params->'requests')='array' THEN snapshot.request_params->'requests'
      ELSE '[]'::jsonb END) request
      WHERE request = jsonb_build_object('companyCode',c.company_code,'divisionCode',c.division_code))
    AND NOT EXISTS (SELECT FROM jsonb_array_elements(CASE
      WHEN jsonb_typeof(snapshot.request_params->'requests')='array' THEN snapshot.request_params->'requests'
      ELSE '[]'::jsonb END) request
      WHERE jsonb_typeof(request)<>'object' OR request->>'companyCode' IS DISTINCT FROM c.company_code
        OR request - ARRAY['companyCode','divisionCode']::text[]<>'{}'::jsonb)
    AND NOT EXISTS (SELECT FROM jsonb_array_elements(CASE
      WHEN jsonb_typeof(snapshot.request_params->'orphanedWithoutItemHeader')='array'
        THEN snapshot.request_params->'orphanedWithoutItemHeader' ELSE '[]'::jsonb END) orphan
      WHERE orphan->>'divisionCode'=c.division_code AND orphan->>'itemNo'=c.source_item_number)
    -- A later incomplete/failed full attempt is disclosed as unknown, never current.
    AND NOT EXISTS (SELECT FROM coldlion.sync_run newer
      WHERE newer.endpoint='/itemDetails' AND newer.company_code=c.company_code
        AND newer.request_params @> '{"fullSnapshot":true}'::jsonb
        AND newer.started_at>snapshot.started_at),false) AS scope_complete
) proof;
REVOKE ALL ON plm.hts_evaluation_prepack_membership FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT (style_number,company_code,division_code,detail_matched_count,state,observed_at,source_complete,source_as_of)
  ON plm.hts_evaluation_prepack_membership TO designflow_hts_evaluation_read;
COMMENT ON VIEW plm.hts_evaluation_prepack_membership IS
  '#5447 private canonical parent-marker evidence. Filter requested normalized styles before aggregation; caller rejects multiple contexts. source_complete proves the recorded canonical snapshot only; source_as_of is not a promise of current ERP state. Caller/root must assess age; unknown eligibility must not be submitted.';

ALTER VIEW plm.hts_evaluation_prepack_membership OWNER TO designflow_hts_prepack_projection_owner;
REVOKE CREATE ON SCHEMA plm FROM designflow_hts_prepack_projection_owner;

REVOKE designflow_hts_prepack_projection_owner FROM postgres GRANTED BY postgres;

DO $verify$
DECLARE original jsonb; actual jsonb;
BEGIN
  original:=current_setting('hts.prepack_original_membership')::jsonb;
  SELECT jsonb_build_object('grantor',m.grantor::text,'admin',m.admin_option,'inherit',m.inherit_option,'set',m.set_option)
    INTO actual FROM pg_auth_members m
    WHERE m.roleid='designflow_hts_prepack_projection_owner'::regrole
      AND m.member=current_user::regrole;
  IF coalesce(actual,'null'::jsonb)<>original
     OR has_schema_privilege('designflow_hts_prepack_projection_owner','plm','CREATE')
     OR pg_has_role('designflow_hts_evaluation_read','designflow_hts_prepack_projection_owner','SET')
     OR has_table_privilege('designflow_hts_prepack_projection_owner','plm.item','INSERT,UPDATE,DELETE')
     OR has_table_privilege('designflow_hts_prepack_projection_owner','coldlion.item_detail','INSERT,UPDATE,DELETE')
     OR has_table_privilege('designflow_hts_prepack_projection_owner','coldlion.sync_run','INSERT,UPDATE,DELETE')
     OR has_column_privilege('designflow_hts_evaluation_read','plm.item','raw','SELECT')
     OR EXISTS (SELECT FROM pg_roles WHERE rolname='designflow_hts_prepack_projection_owner'
        AND (rolcanlogin OR rolinherit OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls))
     OR EXISTS (SELECT FROM pg_auth_members WHERE roleid='designflow_hts_prepack_projection_owner'::regrole
        AND member<>current_user::regrole) THEN
    RAISE EXCEPTION 'REFUSED: final constrained projection authority mismatch';
  END IF;
END
$verify$;
