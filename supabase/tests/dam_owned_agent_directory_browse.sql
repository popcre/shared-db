-- Disposable database only. Normal signup triggers remain enabled.
BEGIN;
DO $$ BEGIN
 IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='auth.users'::regclass AND tgname IN ('on_auth_user_created','on_auth_user_created_popdam') AND tgenabled='O' AND NOT tgisinternal) IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'normal signup triggers required'; END IF;
END $$;
INSERT INTO public.invitations(email) VALUES ('browse-5652-a@fixture.invalid'),('browse-5652-b@fixture.invalid');
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('56520000-0000-0000-0000-000000000001','browse-5652-a@fixture.invalid','{}','{}'),
 ('56520000-0000-0000-0000-000000000002','browse-5652-b@fixture.invalid','{}','{}');
INSERT INTO public.agent_registrations(id,agent_name,agent_type,agent_key_hash) VALUES
 ('56520000-0000-0000-0000-000000000011','browse-5652-bridge','bridge','fixture-browse-5652-bridge'),
 ('56520000-0000-0000-0000-000000000012','browse-5652-windows','windows-render','fixture-browse-5652-windows');
DO $test$
DECLARE
 a uuid := '56520000-0000-0000-0000-000000000001';
 b uuid := '56520000-0000-0000-0000-000000000002';
 bridge uuid := '56520000-0000-0000-0000-000000000011';
 win uuid := '56520000-0000-0000-0000-000000000012';
 r1 uuid := '56520000-0000-0000-0000-000000000021';
 r2 uuid := '56520000-0000-0000-0000-000000000022';
 r3 uuid := '56520000-0000-0000-0000-000000000023';
 result jsonb;
 payload jsonb := '[{"name":"日本語 directory","is_dir":true,"extra":{"preserved":"yes"}},{"name":"art.ai","is_dir":false,"size":123}]';
 original jsonb;
 next_before jsonb;
 role_name text;
 fn regprocedure;
BEGIN
 IF public.admit_agent_directory_browse(bridge,r1,a,'')->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'empty-root admission'; END IF;
 IF public.admit_agent_directory_browse(bridge,r1,a,'')->>'status' IS DISTINCT FROM 'idempotent' THEN RAISE EXCEPTION 'exact retry'; END IF;
 BEGIN PERFORM public.admit_agent_directory_browse(bridge,r1,b,''); RAISE EXCEPTION 'actor mismatch accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.admit_agent_directory_browse(win,r1,a,''); RAISE EXCEPTION 'agent mismatch accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.admit_agent_directory_browse(bridge,r1,a,'other'); RAISE EXCEPTION 'path mismatch accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 IF public.admit_agent_directory_browse(bridge,r2,b,'private')->>'status' IS DISTINCT FROM 'busy' THEN RAISE EXCEPTION 'busy admission'; END IF;
 IF public.get_agent_directory_browse_result(r1,b) IS NOT NULL OR public.get_agent_directory_browse_result(NULL,b) IS NOT NULL THEN RAISE EXCEPTION 'actor result leaked'; END IF;
 IF public.cancel_agent_directory_browse(r1,b) IS NOT FALSE THEN RAISE EXCEPTION 'other actor cancelled'; END IF;
 IF public.complete_agent_directory_browse(bridge,r1,payload) IS NOT FALSE THEN RAISE EXCEPTION 'unclaimed report accepted'; END IF;
 result:=public.claim_agent_directory_browse(bridge);
 IF result IS DISTINCT FROM jsonb_build_object('request_id',r1,'path','') OR public.claim_agent_directory_browse(bridge) IS NOT NULL THEN RAISE EXCEPTION 'claim wire/lease'; END IF;
 IF public.complete_agent_directory_browse(win,r1,payload) IS NOT FALSE THEN RAISE EXCEPTION 'spoofed agent'; END IF;
 IF public.complete_agent_directory_browse(bridge,r1,'{}') IS NOT FALSE OR public.complete_agent_directory_browse(bridge,r1,'[{}]') IS NOT FALSE
    OR public.complete_agent_directory_browse(bridge,r1,'[{"name":1,"is_dir":true}]') IS NOT FALSE
    OR public.complete_agent_directory_browse(bridge,r1,'[{"name":"x","is_dir":"yes"}]') IS NOT FALSE THEN RAISE EXCEPTION 'malformed result accepted'; END IF;
 UPDATE dam.agent_directory_browse_requests SET claim_until=clock_timestamp()-interval '1 second' WHERE request_id=r1;
 IF public.claim_agent_directory_browse(bridge) IS NULL THEN RAISE EXCEPTION 'lease not redelivered'; END IF;
 IF public.complete_agent_directory_browse(bridge,r1,payload) IS NOT TRUE THEN RAISE EXCEPTION 'completion rejected'; END IF;
 original:=public.get_agent_directory_browse_result(r1,a);
 IF original->>'agent_id' IS DISTINCT FROM bridge::text OR original->'listed_at' IS DISTINCT FROM original->'completed_at' THEN RAISE EXCEPTION 'wire aliases'; END IF;
 IF original->'entries' IS DISTINCT FROM payload OR original->>'path' IS DISTINCT FROM '' OR original->>'status' IS DISTINCT FROM 'completed' THEN RAISE EXCEPTION 'full original result not preserved'; END IF;
 IF public.complete_agent_directory_browse(bridge,r1,payload) IS NOT TRUE OR public.complete_agent_directory_browse(bridge,r1,'[]') IS NOT FALSE
    OR public.get_agent_directory_browse_result(r1,a) IS DISTINCT FROM original THEN RAISE EXCEPTION 'duplicate changed first result'; END IF;
 IF public.admit_agent_directory_browse(bridge,r2,b,E'\\\\server\\share\\日本語')->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'next request'; END IF;
 IF public.get_agent_directory_browse_result(r1,a) IS DISTINCT FROM original OR public.get_agent_directory_browse_result(NULL,a) IS DISTINCT FROM original THEN RAISE EXCEPTION 'next actor erased prior result'; END IF;
 next_before:=public.get_agent_directory_browse_result(r2,b);
 IF public.complete_agent_directory_browse(bridge,r1,'[]') IS NOT FALSE THEN RAISE EXCEPTION 'old report replaced result'; END IF;
 IF public.get_agent_directory_browse_result(r1,a) IS DISTINCT FROM original OR public.get_agent_directory_browse_result(r2,b) IS DISTINCT FROM next_before THEN RAISE EXCEPTION 'changed old response modified either preimage'; END IF;
 IF public.cancel_agent_directory_browse(r2,b) IS NOT TRUE OR public.complete_agent_directory_browse(bridge,r2,payload) IS NOT FALSE THEN RAISE EXCEPTION 'cancel/late report'; END IF;
 IF public.admit_agent_directory_browse(win,r3,a,'Unicode 日本語')->>'status' IS DISTINCT FROM 'admitted' OR public.claim_agent_directory_browse(win) IS NULL THEN RAISE EXCEPTION 'Windows independent claim'; END IF;
 UPDATE dam.agent_directory_browse_requests SET expires_at=clock_timestamp()-interval '1 second' WHERE request_id=r3;
 IF public.complete_agent_directory_browse(win,r3,payload) IS NOT FALSE OR public.claim_agent_directory_browse(win) IS NOT NULL
    OR public.get_agent_directory_browse_result(r3,a)->>'status' IS DISTINCT FROM 'expired' THEN RAISE EXCEPTION 'expired report/claim/get'; END IF;
 BEGIN PERFORM public.admit_agent_directory_browse(win,r2,a,'new'); RAISE EXCEPTION 'request identity reused'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 IF public.admit_agent_directory_browse(win,'56520000-0000-0000-0000-000000000024',a,'')->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'expired row prevented admission'; END IF;
 IF public.get_agent_directory_browse_result(NULL,a)->>'request_id' IS DISTINCT FROM '56520000-0000-0000-0000-000000000024' THEN RAISE EXCEPTION 'actor latest adapter'; END IF;
END $test$;
DO $acl$
DECLARE role_name text; fn regprocedure;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated'] LOOP
  IF has_table_privilege(role_name,'dam.agent_directory_browse_requests','SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'table access leaked to %',role_name; END IF;
  FOREACH fn IN ARRAY ARRAY['public.admit_agent_directory_browse(uuid,uuid,uuid,text)'::regprocedure,'public.claim_agent_directory_browse(uuid)'::regprocedure,'public.complete_agent_directory_browse(uuid,uuid,jsonb) IS NOT FALSE'::regprocedure,'public.get_agent_directory_browse_result(uuid,uuid)'::regprocedure,'public.cancel_agent_directory_browse(uuid,uuid) IS NOT FALSE'::regprocedure] LOOP
   IF has_function_privilege(role_name,fn,'EXECUTE') OR NOT has_function_privilege('service_role',fn,'EXECUTE') THEN RAISE EXCEPTION 'service-only ACL failed % %',role_name,fn; END IF;
  END LOOP;
 END LOOP;
END $acl$;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN PERFORM * FROM dam.agent_directory_browse_requests; RAISE EXCEPTION 'anon table read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_agent_directory_browse_result(NULL,NULL); RAISE EXCEPTION 'anon RPC'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM * FROM dam.agent_directory_browse_requests; RAISE EXCEPTION 'authenticated table read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_agent_directory_browse_result(NULL,NULL); RAISE EXCEPTION 'authenticated RPC'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$ BEGIN
 IF public.get_agent_directory_browse_result('56520000-0000-0000-0000-000000000021','56520000-0000-0000-0000-000000000001')->>'status' IS DISTINCT FROM 'completed' THEN RAISE EXCEPTION 'actual service role invocation failed'; END IF;
 IF public.admit_agent_directory_browse('56520000-0000-0000-0000-000000000011','56520000-0000-0000-0000-000000000026','56520000-0000-0000-0000-000000000001','service')->>'status' IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'service admission'; END IF;
 IF public.claim_agent_directory_browse('56520000-0000-0000-0000-000000000011')->>'request_id' IS DISTINCT FROM '56520000-0000-0000-0000-000000000026' THEN RAISE EXCEPTION 'service claim'; END IF;
 IF public.complete_agent_directory_browse('56520000-0000-0000-0000-000000000011','56520000-0000-0000-0000-000000000026','[]') IS NOT TRUE THEN RAISE EXCEPTION 'service completion'; END IF;
 IF public.cancel_agent_directory_browse('56520000-0000-0000-0000-000000000026','56520000-0000-0000-0000-000000000001') IS NOT FALSE THEN RAISE EXCEPTION 'service cancel terminal'; END IF;
END $$;
RESET ROLE;
-- At most 100 old own-agent terminal rows are removed, never another agent's.
INSERT INTO dam.agent_directory_browse_requests(request_id,agent_id,requested_by,path,status,requested_at,expires_at)
 SELECT gen_random_uuid(),'56520000-0000-0000-0000-000000000011','56520000-0000-0000-0000-000000000001','retained','completed',clock_timestamp()-interval '25 hours',clock_timestamp()-interval '24 hours' FROM generate_series(1,101);
INSERT INTO dam.agent_directory_browse_requests(request_id,agent_id,requested_by,path,status,requested_at,expires_at)
 VALUES(gen_random_uuid(),'56520000-0000-0000-0000-000000000012','56520000-0000-0000-0000-000000000001','other-agent','completed',clock_timestamp()-interval '25 hours',clock_timestamp()-interval '24 hours');
SELECT public.admit_agent_directory_browse('56520000-0000-0000-0000-000000000011','56520000-0000-0000-0000-000000000025','56520000-0000-0000-0000-000000000001','cleanup');
DO $$ BEGIN
 IF (SELECT count(*) FROM dam.agent_directory_browse_requests WHERE path='retained') IS DISTINCT FROM 1 OR (SELECT count(*) FROM dam.agent_directory_browse_requests WHERE path='other-agent') IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'cleanup bound or agent scope'; END IF;
END $$;
-- Transient history must never obstruct normal unpair/user deletion.
DELETE FROM public.agent_registrations WHERE id='56520000-0000-0000-0000-000000000011';
DO $$ BEGIN IF EXISTS(SELECT 1 FROM dam.agent_directory_browse_requests WHERE agent_id='56520000-0000-0000-0000-000000000011') THEN RAISE EXCEPTION 'unpair cascade'; END IF; END $$;
DELETE FROM auth.users WHERE id='56520000-0000-0000-0000-000000000001';
DO $$ BEGIN IF EXISTS(SELECT 1 FROM dam.agent_directory_browse_requests WHERE requested_by='56520000-0000-0000-0000-000000000001') THEN RAISE EXCEPTION 'user deletion cascade'; END IF; END $$;
ROLLBACK;
