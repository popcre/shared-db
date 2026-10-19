-- #4493: restore the production backend login in the DesignFlow actor check.
--
-- The 2026-10-17 Cloud SQL -> Supabase host cutover (#770) renamed the Cloud SQL
-- dump schema into dflow_prod. That replaced the repository-managed
-- dflow_prod.current_designflow_user_id() with the Cloud SQL copy, whose
-- session_user allowlist is ('postgres', 'designflow'). Production now logs in
-- as designflow_prod_backend_runtime (#2873), so every backend workflow write
-- (RFQ Step changes, SYS-RFQ-WF-004) fails with 42501.
--
-- This redefines the function from the live production body, read on
-- 2026-10-19, changing only the allowlist to add designflow_prod_backend_runtime,
-- as 20261006235109 had. CREATE OR REPLACE keeps the owner and grants.

create or replace function dflow_prod.current_designflow_user_id()
returns integer
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'dflow_prod'
as $function$
DECLARE
  v_backend_id_text text := nullif(current_setting('request.designflow.actor_id', true), '');
  v_backend_email text := lower(nullif(btrim(
    current_setting('request.designflow.actor_email', true)
  ), ''));
  v_user_id integer;
  v_count integer;
BEGIN
  IF v_backend_id_text IS NULL AND v_backend_email IS NULL THEN
    RAISE EXCEPTION 'an authenticated DesignFlow actor is required' USING ERRCODE = '42501';
  END IF;

  IF session_user::text NOT IN ('postgres', 'designflow', 'designflow_prod_backend_runtime') THEN
    RAISE EXCEPTION
      'backend actor context requires the DesignFlow backend database role (session_user=%)',
      session_user
      USING ERRCODE = '42501';
  END IF;

  IF v_backend_id_text IS NULL OR v_backend_email IS NULL THEN
    RAISE EXCEPTION 'backend actor id and email are both required' USING ERRCODE = '22004';
  END IF;

  IF v_backend_id_text !~ '^[1-9][0-9]*$'
     OR v_backend_id_text::numeric > 2147483647 THEN
    RAISE EXCEPTION 'backend actor id is invalid' USING ERRCODE = '22023';
  END IF;

  v_user_id := v_backend_id_text::integer;
  SELECT count(*)::integer
    INTO v_count
    FROM dflow_prod.users u
   WHERE u.id = v_user_id
     AND lower(btrim(u.email)) = v_backend_email
     AND lower(btrim(u.status)) = 'active';

  IF v_count = 0 THEN
    RAISE EXCEPTION 'backend actor is missing, inactive, or does not match its token email'
      USING ERRCODE = '42501';
  END IF;

  RETURN v_user_id;
END
$function$;
