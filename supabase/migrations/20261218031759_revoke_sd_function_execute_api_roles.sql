-- #6455: revoke superfluous anon/authenticated EXECUTE on 12 of the 17
-- security-definer signatures the #6416 measurement dispositioned `revoke`.
-- Part of the #2326 program (database efficiency & Data API security).
--
-- Evidence: docs/verification/database-efficiency/20261116T050000Z-step6-
-- 6416-sd-rpc-matrix/sd-rpc-matrix.md (2026-11-16).
--
-- WHY
-- ---
-- 11 of the 12 signatures are in plm, dflow_prod, or net. The Data API
-- exposes public, graphql_public, api, crm, pim, core, and app as of
-- 2026-11-15. The remaining signature is
-- public.lock_down_new_public_function_execute(), an event-trigger
-- function in the same class as
-- the trigger-function grants revoked in 20261116013153 (#6415). SQL-level
-- callers (postgres / service_role / the event trigger itself) are unaffected:
-- their grants are untouched.
--
-- Call out: net.http_get / net.http_post carry anon EXECUTE — non-exposed
-- today, but a landmine if `net` ever enters pgrst.db_schemas.
--
-- WHY `from public, anon, authenticated` AND NOT JUST `from anon, authenticated`
-- -----------------------------------------------------------------------
-- Most of these functions carry no explicit role grant at all: their ACL is
-- the function default (PUBLIC EXECUTE). Revoking the named roles alone is a
-- no-op — anon/authenticated still hold EXECUTE through PUBLIC and the census
-- query would never drop. The PUBLIC pseudo-role is the real grant here (same
-- trap as #6415 and the 2026-07-29 public EXECUTE lockdown). postgres /
-- service_role / admin-role grants are left untouched.
--
-- SCOPE (pinned at authoring time 2026-11-17 10:30 PM EST)
-- -----
-- Preserve existing grants on the DAM order date helper, both PLM source
-- resolution setters, and both target-missing helpers. The order list and
-- source resolution views and established authenticated SQL contracts depend
-- on these grants. The API setters and public.rls_auto_enable (#6456) are
-- also outside this migration.
--
-- Existence-guarded loop (repository pattern 20260729130000_production_safe_
-- public_execute_lockdown.sql): each signature is resolved through
-- to_regprocedure and skipped when absent, so this migration cannot abort on
-- an environment where one of the functions has not been created (preview and
-- production have diverged in both directions — standing fact 11). REVOKE of
-- an unheld privilege is a silent no-op, so re-running is harmless.
--
-- ROLLBACK (named)
-- ----------------
-- Forward migration re-granting EXECUTE on exactly these signatures:
--   grant execute on function dflow_prod.claim_sample_shipment_notice(bigint) to public, anon, authenticated;
--   grant execute on function dflow_prod.pack_sample_reservation(uuid,integer,bigint,text,text,text,text,text,text,text,text) to public, anon, authenticated;
--   grant execute on function dflow_prod.post_sample_remote_request_event(uuid,text,text,text,text,text,text,jsonb) to public, anon, authenticated;
--   grant execute on function dflow_prod.record_item_workflow_action(integer,integer,text,uuid,text,text,boolean,text,text,text,jsonb) to public, anon, authenticated;
--   grant execute on function dflow_prod.reserve_sample_remote_request_item(uuid,text,text,text,text) to public, anon, authenticated;
--   grant execute on function dflow_prod.set_item_user_assignment(integer,text,integer,boolean,jsonb) to public, anon, authenticated;
--   grant execute on function net.http_get(text,jsonb,jsonb,integer) to public, anon, authenticated;
--   grant execute on function net.http_post(text,jsonb,jsonb,jsonb,integer) to public, anon, authenticated;
--   grant execute on function plm.coldlion_merch_group_candidates(text,text) to public, anon, authenticated;
--   grant execute on function plm.latest_sesame_capture() to public, anon, authenticated;
--   grant execute on function plm.prepack_role(text,text,text) to public, anon, authenticated;
--   grant execute on function public.lock_down_new_public_function_execute() to public, anon, authenticated;
-- For names whose only pre-change grant was the function default, `to public`
-- restores the original state; the explicit anon/authenticated grants it also
-- writes match the explicit grants that existed before (net/http, dflow_prod).
-- The event trigger that installs lock_down_new_public_function_execute is
-- unaffected: trigger creation checks EXECUTE at CREATE TRIGGER time and the
-- event trigger itself fires as its owner.

begin;

do $$
declare
  r record;
  n integer := 0;
  absent integer := 0;
  leftover text;
  leftover_count integer;
begin
  for r in
    select t.sig
    from (values
      ('dflow_prod.claim_sample_shipment_notice(bigint)'),
      ('dflow_prod.pack_sample_reservation(uuid,integer,bigint,text,text,text,text,text,text,text,text)'),
      ('dflow_prod.post_sample_remote_request_event(uuid,text,text,text,text,text,text,jsonb)'),
      ('dflow_prod.record_item_workflow_action(integer,integer,text,uuid,text,text,boolean,text,text,text,jsonb)'),
      ('dflow_prod.reserve_sample_remote_request_item(uuid,text,text,text,text)'),
      ('dflow_prod.set_item_user_assignment(integer,text,integer,boolean,jsonb)'),
      ('net.http_get(text,jsonb,jsonb,integer)'),
      ('net.http_post(text,jsonb,jsonb,jsonb,integer)'),
      ('plm.coldlion_merch_group_candidates(text,text)'),
      ('plm.latest_sesame_capture()'),
      ('plm.prepack_role(text,text,text)'),
      ('public.lock_down_new_public_function_execute()')
    ) as t(sig)
  loop
    if to_regprocedure(r.sig) is null then
      absent := absent + 1;
      raise notice 'signature absent on this database, skipped: %', r.sig;
    else
      execute format(
        'revoke execute on function %s from public, anon, authenticated', r.sig);
      n := n + 1;
    end if;
  end loop;

  raise notice 'revoked EXECUTE on % of 12 in-scope signatures (% absent)',
    n, absent;

  -- Assert: no in-scope signature that exists on this database still carries
  -- anon or authenticated EXECUTE.
  select count(*), string_agg(t.sig, ', ')
    into leftover_count, leftover
  from (values
    ('dflow_prod.claim_sample_shipment_notice(bigint)'),
    ('dflow_prod.pack_sample_reservation(uuid,integer,bigint,text,text,text,text,text,text,text,text)'),
    ('dflow_prod.post_sample_remote_request_event(uuid,text,text,text,text,text,text,jsonb)'),
    ('dflow_prod.record_item_workflow_action(integer,integer,text,uuid,text,text,boolean,text,text,text,jsonb)'),
    ('dflow_prod.reserve_sample_remote_request_item(uuid,text,text,text,text)'),
    ('dflow_prod.set_item_user_assignment(integer,text,integer,boolean,jsonb)'),
    ('net.http_get(text,jsonb,jsonb,integer)'),
    ('net.http_post(text,jsonb,jsonb,jsonb,integer)'),
    ('plm.coldlion_merch_group_candidates(text,text)'),
    ('plm.latest_sesame_capture()'),
    ('plm.prepack_role(text,text,text)'),
    ('public.lock_down_new_public_function_execute()')
  ) as t(sig)
  where to_regprocedure(t.sig) is not null
    and (has_function_privilege('anon', to_regprocedure(t.sig), 'EXECUTE')
      or has_function_privilege('authenticated', to_regprocedure(t.sig), 'EXECUTE'));

  if leftover_count > 0 then
    raise exception 'in-scope signatures still API-executable after revoke: %',
      leftover;
  end if;
end
$$;

commit;
