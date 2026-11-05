-- #5652 / PopDAM #468: private, per-request directory browse custody.
-- No legacy admin_config rows or unrelated job leases are changed.
CREATE TABLE dam.agent_directory_browse_requests (
  request_id uuid PRIMARY KEY,
  agent_id uuid NOT NULL REFERENCES public.agent_registrations(id) ON DELETE CASCADE,
  requested_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  path text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','claimed','completed','cancelled','expired')),
  requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL DEFAULT (clock_timestamp() + interval '120 seconds'),
  claim_until timestamptz,
  completed_at timestamptz,
  entries jsonb CHECK (entries IS NULL OR jsonb_typeof(entries) = 'array')
);
CREATE UNIQUE INDEX agent_directory_browse_one_active ON dam.agent_directory_browse_requests(agent_id)
  WHERE status IN ('pending','claimed');
CREATE INDEX agent_directory_browse_cleanup ON dam.agent_directory_browse_requests(agent_id,requested_at,request_id)
  WHERE status IN ('completed','cancelled','expired');
CREATE INDEX agent_directory_browse_actor_latest ON dam.agent_directory_browse_requests(requested_by,requested_at DESC,request_id DESC);
ALTER TABLE dam.agent_directory_browse_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON dam.agent_directory_browse_requests FROM PUBLIC, anon, authenticated;
-- No direct service table access is required: only the five service RPCs.
REVOKE ALL ON dam.agent_directory_browse_requests FROM service_role;

CREATE FUNCTION public.admit_agent_directory_browse(p_agent_id uuid,p_request_id uuid,p_requested_by uuid,p_path text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET statement_timeout = '8s' AS $fn$
DECLARE r dam.agent_directory_browse_requests%ROWTYPE;
BEGIN
  IF p_agent_id IS NULL OR p_request_id IS NULL OR p_requested_by IS NULL OR p_path IS NULL THEN
    RAISE EXCEPTION 'Directory browse requires agent, request, actor and path' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.agent_registrations WHERE id=p_agent_id AND agent_type IN ('bridge','windows-render')) THEN
    RAISE EXCEPTION 'Unsupported directory browse agent' USING ERRCODE='22023';
  END IF;
  UPDATE dam.agent_directory_browse_requests SET status='expired',claim_until=NULL
    WHERE agent_id=p_agent_id AND status IN ('pending','claimed') AND expires_at<=clock_timestamp();
  DELETE FROM dam.agent_directory_browse_requests WHERE request_id IN (
    SELECT request_id FROM dam.agent_directory_browse_requests
    WHERE agent_id=p_agent_id AND status IN ('completed','cancelled','expired')
      AND requested_at<clock_timestamp()-interval '24 hours'
    ORDER BY requested_at,request_id LIMIT 100 FOR UPDATE SKIP LOCKED
  );
  INSERT INTO dam.agent_directory_browse_requests(request_id,agent_id,requested_by,path)
    VALUES(p_request_id,p_agent_id,p_requested_by,p_path) ON CONFLICT DO NOTHING
    RETURNING * INTO r;
  IF FOUND THEN RETURN jsonb_build_object('status','admitted','request_id',r.request_id,'expires_at',r.expires_at); END IF;
  -- Separate statement sees the committed winner after a concurrent insert waited.
  SELECT * INTO r FROM dam.agent_directory_browse_requests WHERE request_id=p_request_id;
  IF FOUND THEN
    IF r.agent_id=p_agent_id AND r.requested_by=p_requested_by AND r.path=p_path THEN
      RETURN jsonb_build_object('status','idempotent','request_id',r.request_id,'expires_at',r.expires_at);
    END IF;
    RAISE EXCEPTION 'Directory browse request identity conflict' USING ERRCODE='22023';
  END IF;
  RETURN jsonb_build_object('status','busy');
END $fn$;

CREATE FUNCTION public.claim_agent_directory_browse(p_agent_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET statement_timeout = '8s' AS $fn$
DECLARE r dam.agent_directory_browse_requests%ROWTYPE;
BEGIN
  WITH candidate AS (
    SELECT request_id FROM dam.agent_directory_browse_requests
    WHERE agent_id=p_agent_id AND expires_at>clock_timestamp()
      AND (status='pending' OR (status='claimed' AND claim_until<=clock_timestamp()))
    FOR UPDATE SKIP LOCKED LIMIT 1
  ) UPDATE dam.agent_directory_browse_requests b SET status='claimed',claim_until=LEAST(clock_timestamp()+interval '30 seconds',b.expires_at)
    FROM candidate c WHERE b.request_id=c.request_id AND b.expires_at>clock_timestamp() RETURNING b.* INTO r;
  IF NOT FOUND OR r.expires_at<=clock_timestamp() THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('request_id',r.request_id,'path',r.path);
END $fn$;

CREATE FUNCTION public.complete_agent_directory_browse(p_agent_id uuid,p_request_id uuid,p_entries jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET statement_timeout = '8s' AS $fn$
DECLARE r dam.agent_directory_browse_requests%ROWTYPE;
BEGIN
  IF p_entries IS NULL OR jsonb_typeof(p_entries)<>'array' THEN RETURN false; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_entries) e
    WHERE jsonb_typeof(e)<>'object' OR jsonb_typeof(e->'name') IS DISTINCT FROM 'string'
      OR jsonb_typeof(e->'is_dir') IS DISTINCT FROM 'boolean') THEN RETURN false; END IF;
  -- Check the absolute deadline AFTER any row-lock wait, not before it.
  SELECT * INTO r FROM dam.agent_directory_browse_requests
    WHERE request_id=p_request_id AND agent_id=p_agent_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF r.status='completed' THEN RETURN r.entries IS NOT DISTINCT FROM p_entries; END IF;
  IF r.status<>'claimed' OR r.expires_at<=clock_timestamp() THEN RETURN false; END IF;
  UPDATE dam.agent_directory_browse_requests SET status='completed',completed_at=clock_timestamp(),entries=p_entries,claim_until=NULL
    WHERE request_id=p_request_id AND agent_id=p_agent_id;
  RETURN true;
END $fn$;

CREATE FUNCTION public.get_agent_directory_browse_result(p_request_id uuid,p_requested_by uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET statement_timeout = '8s' AS $fn$
DECLARE r dam.agent_directory_browse_requests%ROWTYPE;
BEGIN
  SELECT * INTO r FROM dam.agent_directory_browse_requests
    WHERE requested_by=p_requested_by AND (p_request_id IS NULL OR request_id=p_request_id)
    ORDER BY requested_at DESC,request_id DESC LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('request_id',r.request_id,'agent_id',r.agent_id,'path',r.path,
    'status',CASE WHEN r.status IN ('pending','claimed') AND r.expires_at<=clock_timestamp() THEN 'expired' ELSE r.status END,
    'requested_at',r.requested_at,'expires_at',r.expires_at,'completed_at',r.completed_at,'listed_at',r.completed_at,'entries',r.entries);
END $fn$;

CREATE FUNCTION public.cancel_agent_directory_browse(p_request_id uuid,p_requested_by uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET statement_timeout = '8s' AS $fn$
BEGIN
  UPDATE dam.agent_directory_browse_requests SET status='cancelled',claim_until=NULL
    WHERE request_id=p_request_id AND requested_by=p_requested_by AND status IN ('pending','claimed');
  RETURN FOUND;
END $fn$;

REVOKE ALL ON FUNCTION public.admit_agent_directory_browse(uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.claim_agent_directory_browse(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.complete_agent_directory_browse(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_agent_directory_browse_result(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.cancel_agent_directory_browse(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admit_agent_directory_browse(uuid,uuid,uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_agent_directory_browse(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_agent_directory_browse(uuid,uuid,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_agent_directory_browse_result(uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.cancel_agent_directory_browse(uuid,uuid) TO service_role;
