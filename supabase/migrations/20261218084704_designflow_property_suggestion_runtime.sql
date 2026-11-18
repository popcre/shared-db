-- Issue #6693: restore the DesignFlow Core SKU property suggestion in production.
-- derived-from: 20261201210000
-- The shared service login gets only the existing read-only SKU result. A
-- separate, non-login owner receives the lookup's exact column privileges.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $preflight$
BEGIN
  IF NOT EXISTS (
    SELECT FROM pg_catalog.pg_proc
    WHERE oid = pg_catalog.to_regprocedure('plm.suggested_property_for_sku(text)')
      AND NOT prosecdef
      AND provolatile = 's'
      AND pg_catalog.md5(prosrc) = '5a545f4b0e46a3b0b596000216d92163'
  ) THEN
    RAISE EXCEPTION 'Property suggestion source differs from the reviewed invoker lookup';
  END IF;
END
$preflight$;

CREATE ROLE designflow_property_suggestion_reader
  NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE SCHEMA plm_property_suggestion_private;
REVOKE ALL ON SCHEMA plm_property_suggestion_private
  FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA plm TO designflow_property_suggestion_reader;

GRANT SELECT (item_no, item_pkey, slot_no, mg_code) ON plm.coldlion_item_merch_group
  TO designflow_property_suggestion_reader;
GRANT SELECT (id, file_name) ON plm.dcp_asset
  TO designflow_property_suggestion_reader;
GRANT SELECT (dcp_asset_id, dcp_property_id) ON plm.dcp_asset_property_observation
  TO designflow_property_suggestion_reader;
GRANT SELECT (id, source_id) ON plm.dcp_property
  TO designflow_property_suggestion_reader;
GRANT SELECT (dcp_source_id, mg_code, mg_desc, confidence) ON plm.dcp_property_mg06_crosswalk
  TO designflow_property_suggestion_reader;
GRANT SELECT (sku, file_name, style_guide_file_id) ON public.sku_files_used
  TO designflow_property_suggestion_reader;
GRANT SELECT (id, licensor_name) ON public.style_guide_files
  TO designflow_property_suggestion_reader;

CREATE POLICY property_suggestion_reader ON plm.dcp_asset
  FOR SELECT TO designflow_property_suggestion_reader USING (true);
CREATE POLICY property_suggestion_reader ON plm.dcp_asset_property_observation
  FOR SELECT TO designflow_property_suggestion_reader USING (true);
CREATE POLICY property_suggestion_reader ON plm.dcp_property
  FOR SELECT TO designflow_property_suggestion_reader USING (true);
CREATE POLICY property_suggestion_reader ON plm.dcp_property_mg06_crosswalk
  FOR SELECT TO designflow_property_suggestion_reader USING (true);
CREATE POLICY property_suggestion_reader ON public.sku_files_used
  FOR SELECT TO designflow_property_suggestion_reader USING (true);
CREATE POLICY property_suggestion_reader ON public.style_guide_files
  FOR SELECT TO designflow_property_suggestion_reader USING (true);

-- Retain the exact SQL body and its existing caller ACL, RLS, and ownership.
ALTER FUNCTION plm.suggested_property_for_sku(text)
  RENAME TO suggested_property_for_sku_invoker;
GRANT EXECUTE ON FUNCTION plm.suggested_property_for_sku_invoker(text)
  TO designflow_property_suggestion_reader;

CREATE FUNCTION plm_property_suggestion_private.lookup(p_sku text)
RETURNS TABLE (
  mg_code text,
  mg_desc text,
  file_count bigint,
  basis text,
  file_names text[]
)
LANGUAGE sql STABLE STRICT SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
  SELECT result.* FROM plm.suggested_property_for_sku_invoker(p_sku) AS result;
$function$;

REVOKE ALL ON FUNCTION plm_property_suggestion_private.lookup(text)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION plm.suggested_property_for_sku(p_sku text)
RETURNS TABLE (
  mg_code text,
  mg_desc text,
  file_count bigint,
  basis text,
  file_names text[]
)
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $function$
BEGIN
  IF current_user = 'designflow_prod_backend_runtime' THEN
    RETURN QUERY SELECT result.* FROM plm_property_suggestion_private.lookup(p_sku) AS result;
  ELSE
    RETURN QUERY SELECT result.* FROM plm.suggested_property_for_sku_invoker(p_sku) AS result;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION plm.suggested_property_for_sku(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION plm.suggested_property_for_sku(text) TO authenticated, service_role;

DO $grant$
BEGIN
  -- The separate DesignFlow sandbox uses postgres and has no production login.
  IF EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'designflow_prod_backend_runtime') THEN
    GRANT USAGE ON SCHEMA plm TO designflow_prod_backend_runtime;
    GRANT USAGE ON SCHEMA plm_property_suggestion_private TO designflow_prod_backend_runtime;
    GRANT EXECUTE ON FUNCTION plm_property_suggestion_private.lookup(text) TO designflow_prod_backend_runtime;
    GRANT EXECUTE ON FUNCTION plm.suggested_property_for_sku(text) TO designflow_prod_backend_runtime;
  END IF;
END
$grant$;

-- PostgreSQL requires the migration role to be able to SET ROLE to the new
-- owner, and the new owner to have CREATE in the function's schema.
GRANT designflow_property_suggestion_reader TO postgres WITH INHERIT FALSE, SET TRUE;
GRANT USAGE, CREATE ON SCHEMA plm_property_suggestion_private
  TO designflow_property_suggestion_reader;
ALTER FUNCTION plm_property_suggestion_private.lookup(text)
  OWNER TO designflow_property_suggestion_reader;
REVOKE CREATE ON SCHEMA plm_property_suggestion_private
  FROM designflow_property_suggestion_reader;
REVOKE SET OPTION FOR designflow_property_suggestion_reader FROM postgres;

DO $verify$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_catalog.pg_auth_members
    WHERE roleid = 'designflow_property_suggestion_reader'::regrole
      AND (member <> 'postgres'::regrole OR inherit_option OR set_option)
  ) THEN
    RAISE EXCEPTION 'Property suggestion reader must not be assumable by any application login';
  END IF;
  IF NOT EXISTS (
    SELECT FROM pg_catalog.pg_proc
    WHERE oid = 'plm_property_suggestion_private.lookup(text)'::regprocedure
      AND pg_catalog.pg_get_userbyid(proowner) = 'designflow_property_suggestion_reader'
      AND prosecdef
      AND proconfig = ARRAY['search_path=pg_catalog, pg_temp']
  ) THEN
    RAISE EXCEPTION 'Property suggestion helper must have the dedicated owner and fixed search path';
  END IF;
  IF EXISTS (
    SELECT
    FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS roles(name)
    WHERE pg_catalog.has_schema_privilege(name, 'plm_property_suggestion_private', 'USAGE')
       OR pg_catalog.has_function_privilege(name, 'plm_property_suggestion_private.lookup(text)', 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'Property suggestion helper must not be executable by API roles';
  END IF;
END
$verify$;

COMMIT;
