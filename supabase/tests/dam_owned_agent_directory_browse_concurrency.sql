-- STRICT real two-session test, disposable database ONLY. No skip fallback.
-- Remote fixtures must be committed to be visible to both competing sessions;
-- the exception handler removes them too. No signup trigger is disabled.
CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions;
SET search_path=extensions,public,pg_catalog;
DO $concurrency$
DECLARE
 connection_string text := 'dbname='||current_database();
 outcome text;
 blocked boolean := false;
 contender_pid integer;
 i integer;
BEGIN
 PERFORM dblink_connect('browse_setup',connection_string);
 PERFORM dblink_exec('browse_setup',$setup$
  INSERT INTO public.invitations(email) VALUES('browse-5652-race@fixture.invalid');
  INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES('56520000-0000-0000-0000-000000000101','browse-5652-race@fixture.invalid','{}','{}');
  INSERT INTO public.agent_registrations(id,agent_name,agent_type,agent_key_hash) VALUES('56520000-0000-0000-0000-000000000111','browse-5652-race','bridge','fixture-browse-5652-race');
 $setup$);
 PERFORM dblink_connect('browse_winner',connection_string);
 PERFORM dblink_connect('browse_contender',connection_string);
 SELECT pid INTO contender_pid FROM dblink('browse_contender','SELECT pg_backend_pid()') AS t(pid integer);
 PERFORM dblink_exec('browse_winner','BEGIN');
 SELECT status INTO outcome FROM dblink('browse_winner',$admit$
  SELECT public.admit_agent_directory_browse('56520000-0000-0000-0000-000000000111','56520000-0000-0000-0000-000000000121','56520000-0000-0000-0000-000000000101','race-a')->>'status'
 $admit$) AS t(status text);
 IF outcome IS DISTINCT FROM 'admitted' THEN RAISE EXCEPTION 'first admission failed: %',outcome; END IF;
 PERFORM dblink_send_query('browse_contender',$admit$
  SELECT public.admit_agent_directory_browse('56520000-0000-0000-0000-000000000111','56520000-0000-0000-0000-000000000122','56520000-0000-0000-0000-000000000101','race-b')->>'status'
 $admit$);
 FOR i IN 1..100 LOOP
  PERFORM pg_stat_clear_snapshot();
  SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE pid=contender_pid AND wait_event_type='Lock') INTO blocked;
  EXIT WHEN blocked;
  PERFORM pg_sleep(0.02);
 END LOOP;
 IF NOT blocked OR dblink_is_busy('browse_contender') IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'no actual overlapping lock wait observed'; END IF;
 PERFORM dblink_exec('browse_winner','COMMIT');
 SELECT status INTO outcome FROM dblink_get_result('browse_contender') AS t(status text);
 IF outcome IS DISTINCT FROM 'busy' THEN RAISE EXCEPTION 'concurrent loser did not return busy: %',outcome; END IF;
 IF (SELECT count(*) FROM dam.agent_directory_browse_requests WHERE agent_id='56520000-0000-0000-0000-000000000111' AND status IN ('pending','claimed')) IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'not exactly one active winner'; END IF;
 PERFORM dblink_disconnect('browse_winner');
 PERFORM dblink_disconnect('browse_contender');
 PERFORM dblink_exec('browse_setup',$cleanup$
  DELETE FROM public.agent_registrations WHERE id='56520000-0000-0000-0000-000000000111';
  DELETE FROM auth.users WHERE id='56520000-0000-0000-0000-000000000101';
  DELETE FROM public.invitations WHERE email='browse-5652-race@fixture.invalid';
 $cleanup$);
 PERFORM dblink_disconnect('browse_setup');
 RAISE NOTICE 'PASS: two genuine sessions overlapped; contender waited on lock; exactly one admission won';
EXCEPTION WHEN OTHERS THEN
 -- Release the winner first; close the competing connection before fixture cleanup.
 IF 'browse_winner'=ANY(COALESCE(dblink_get_connections(),ARRAY[]::text[])) THEN
  PERFORM dblink_exec('browse_winner','ROLLBACK'); PERFORM dblink_disconnect('browse_winner');
 END IF;
 IF 'browse_contender'=ANY(COALESCE(dblink_get_connections(),ARRAY[]::text[])) THEN
  PERFORM dblink_cancel_query('browse_contender'); PERFORM dblink_disconnect('browse_contender');
 END IF;
 IF 'browse_setup'=ANY(COALESCE(dblink_get_connections(),ARRAY[]::text[])) THEN
  PERFORM dblink_exec('browse_setup',$cleanup$
   DELETE FROM public.agent_registrations WHERE id='56520000-0000-0000-0000-000000000111';
   DELETE FROM auth.users WHERE id='56520000-0000-0000-0000-000000000101';
   DELETE FROM public.invitations WHERE email='browse-5652-race@fixture.invalid';
  $cleanup$);
  PERFORM dblink_disconnect('browse_setup');
 END IF;
 RAISE;
END $concurrency$;
RESET search_path;
