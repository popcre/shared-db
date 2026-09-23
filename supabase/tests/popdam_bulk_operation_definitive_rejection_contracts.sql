-- popcre/shared-db#3418, claim #3425. Every fixture write rolls back.
begin;

create table if not exists public.admin_config (
  key text not null,
  value jsonb not null,
  updated_at timestamptz default now() not null,
  updated_by uuid
);
do $bootstrap$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.admin_config'::regclass and contype = 'p'
  ) then
    alter table public.admin_config add primary key (key);
  end if;
end $bootstrap$;

-- The helper refuses a false success and verifies failed calls never mutate the
-- BULK_OPERATIONS value. It exists only within this rolled-back test transaction.
create or replace function pg_temp.expect_lease_reset_refusal(
  p_revision bigint,
  p_owner text,
  p_token text,
  p_reason text,
  p_status integer,
  p_error jsonb,
  p_sqlstate text,
  p_key text default 'bulk-tag'
)
returns void
language plpgsql
as $helper$
declare
  v_before jsonb;
  v_after jsonb;
  v_actual text;
  v_rejected boolean := false;
begin
  select value into v_before from public.admin_config where key = 'BULK_OPERATIONS';
  begin
    perform public.reset_bulk_operation_submission_lease(
      p_key, p_revision, p_owner, p_token, p_reason, p_status, p_error);
  exception when others then
    get stacked diagnostics v_actual = returned_sqlstate;
    if v_actual is distinct from p_sqlstate then
      raise exception 'unexpected reset refusal SQLSTATE %, wanted %', v_actual, p_sqlstate;
    end if;
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'unsafe lease reset was accepted';
  end if;
  select value into v_after from public.admin_config where key = 'BULK_OPERATIONS';
  if v_after is distinct from v_before then
    raise exception 'refused lease reset changed stored state';
  end if;
end;
$helper$;

do $test$
declare
  v_claim jsonb;
  v_token text;
  v_claimed jsonb;
  v_reset jsonb;
  v_reclaim jsonb;
  v_new_token text;
  v_job jsonb;
  v_status integer;
  v_marker text;
  v_with_extra jsonb;
  v_error constant jsonb := '{"error":{"message":"synthetic rejection"}}'::jsonb;
begin
  -- Use the real writer to mint the one-time receipt. All later assertions
  -- start from the actual saved revision, owner and digest it produced.
  insert into public.admin_config(key, value, updated_at)
  values ('BULK_OPERATIONS',
          '{"bulk-tag":{"status":"running","state_revision":0,"external_job":{"phase":"prepared"}}}'::jsonb,
          now())
  on conflict (key) do update set value = excluded.value, updated_at = excluded.updated_at;

  v_claim := public.update_bulk_operation(
    'bulk-tag',
    '{"status":"running","external_job":{"phase":"submitting"}}'::jsonb,
    'running', 0, 'worker-A', 120);
  v_token := v_claim ->> 'lease_token';
  if v_claim ->> 'ok' is distinct from 'true'
     or v_claim ->> 'lease_receipt_issued' is distinct from 'true'
     or v_token is null then
    raise exception 'real writer did not issue the fixture receipt';
  end if;
  select value into v_claimed from public.admin_config where key = 'BULK_OPERATIONS';

  -- Invalid or unparsed provider outcomes can never turn an uncertain POST
  -- into another chance to submit. This explicit set records the known
  -- routing, policy, conflict, timeout and retry-shaped refusal cases.
  foreach v_status in array array[200, 401, 402, 403, 404, 405, 406,
                                  407, 408, 409, 410, 411, 412, 413, 414,
                                  415, 416, 417, 418, 419, 420, 421, 423,
                                  424, 425, 426, 427, 428, 429, 430, 431,
                                  449, 451, 499, 500] loop
    perform pg_temp.expect_lease_reset_refusal(
      1, 'worker-A', v_token, 'provider_definitive_rejection',
      v_status, v_error, '22023');
  end loop;
  -- Exhaust the entire 4xx space with the same provider-origin-shaped JSON
  -- evidence: only the two accepted validation statuses may reach a reset.
  for v_status in 400..499 loop
    if v_status not in (400, 422) then
      perform pg_temp.expect_lease_reset_refusal(
        1, 'worker-A', v_token, 'provider_definitive_rejection',
        v_status, v_error, '22023');
    end if;
  end loop;
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'timeout', 400, v_error, '22023');
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'provider_definitive_rejection', 400, null, '22023');
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'provider_definitive_rejection', 400, '{}'::jsonb, '22023');
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'provider_definitive_rejection', 400, '[]'::jsonb, '22023');
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'provider_definitive_rejection', 400, v_error, '22023', '');
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'provider_definitive_rejection', 400, v_error, '22023', null);
  perform pg_temp.expect_lease_reset_refusal(
    null, 'worker-A', v_token, 'provider_definitive_rejection', 400, v_error, '22023');
  perform pg_temp.expect_lease_reset_refusal(
    1, '', v_token, 'provider_definitive_rejection', 400, v_error, '22023');
  perform pg_temp.expect_lease_reset_refusal(
    1, null, v_token, 'provider_definitive_rejection', 400, v_error, '22023');
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', '', 'provider_definitive_rejection', 400, v_error, '22023');
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', null, 'provider_definitive_rejection', 400, v_error, '22023');

  perform pg_temp.expect_lease_reset_refusal(
    0, 'worker-A', v_token, 'provider_definitive_rejection', 400, v_error, '55000');
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-B', v_token, 'provider_definitive_rejection', 400, v_error, '55000');
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', 'wrong-receipt', 'provider_definitive_rejection', 400, v_error, '55000');

  update public.admin_config
  set value = jsonb_set(v_claimed,
    '{bulk-tag,external_job,lease_expires_at}',
    to_jsonb((clock_timestamp() - interval '1 second')::text))
  where key = 'BULK_OPERATIONS';
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'provider_definitive_rejection', 400, v_error, '55000');

  -- A marker cannot be smuggled into a still-submitting phase to bypass the
  -- explicit ambiguity refusal. Each protected marker is checked directly.
  foreach v_marker in array array['ambiguous_since', 'ambiguous_reason',
                                  'ambiguous_prior_phase', 'ambiguous_prior_owner'] loop
    update public.admin_config
    set value = jsonb_set(v_claimed,
      array['bulk-tag', 'external_job', v_marker], '"fixture"'::jsonb)
    where key = 'BULK_OPERATIONS';
    perform pg_temp.expect_lease_reset_refusal(
      1, 'worker-A', v_token, 'provider_definitive_rejection', 400, v_error, '55000');
  end loop;

  update public.admin_config
  set value = jsonb_set(v_claimed,
    '{bulk-tag,external_job,provider_batch_id}', '"bound-fixture"'::jsonb)
  where key = 'BULK_OPERATIONS';
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'provider_definitive_rejection', 400, v_error, '55000');

  update public.admin_config
  set value = jsonb_set(v_claimed,
    '{bulk-tag,external_job,phase}', '"ambiguous_submission"'::jsonb)
  where key = 'BULK_OPERATIONS';
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'provider_definitive_rejection', 400, v_error, '55000');

  update public.admin_config
  set value = jsonb_set(v_claimed, '{bulk-tag,status}', '"stopped"'::jsonb)
  where key = 'BULK_OPERATIONS';
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'provider_definitive_rejection', 400, v_error, '55000');

  -- Positive path: current unexpired holder with exact receipt and revision,
  -- no provider ID, parsed definitive 4xx. Reset consumes the receipt without
  -- issuing another or recording the error body.
  v_with_extra := jsonb_set(
    jsonb_set(
      jsonb_set(v_claimed, '{bulk-tag,external_job,lease_token}', '"stored-fixture"'::jsonb),
      '{bulk-tag,external_job,submitted_at}', '"fixture"'::jsonb),
    '{bulk-tag,external_job,next_poll_at}', '"fixture"'::jsonb);
  update public.admin_config set value = v_with_extra where key = 'BULK_OPERATIONS';
  v_reset := public.reset_bulk_operation_submission_lease(
    'bulk-tag', 1, 'worker-A', v_token,
    'provider_definitive_rejection', 400, v_error);
  v_job := v_reset -> 'operation' -> 'external_job';
  if v_reset ->> 'ok' is distinct from 'true'
     or (v_reset ->> 'state_revision')::bigint is distinct from 2
     or v_reset ->> 'lease_receipt_issued' is distinct from 'false'
     or v_reset ->> 'lease_token' is not null
     or v_job ->> 'phase' is distinct from 'prepared'
     or v_job ? 'submission_owner' or v_job ? 'lease_expires_at'
     or v_job ? 'lease_claimed_at' or v_job ? 'lease_token'
     or v_job ? 'submitted_at' or v_job ? 'next_poll_at'
     or v_job ? 'lease_proof' or v_job ? 'provider_batch_id'
     or (v_job ->> 'last_definitive_rejection_status')::integer is distinct from 400
     or nullif(v_job ->> 'last_definitive_rejection_at', '')::timestamptz is null
     or v_job::text like '%synthetic rejection%' then
    raise exception 'definitive rejection reset did not consume the lease safely';
  end if;

  -- A stale process cannot reset or claim the old revision. The ordinary
  -- guarded claim, not the reset, issues the next receipt to one claimant.
  perform pg_temp.expect_lease_reset_refusal(
    1, 'worker-A', v_token, 'provider_definitive_rejection', 400, v_error, '55000');
  v_reclaim := public.update_bulk_operation(
    'bulk-tag',
    jsonb_set(v_reset -> 'operation', '{external_job,phase}', '"submitting"'::jsonb),
    'running', 1, 'worker-B', 120);
  if v_reclaim ->> 'ok' is distinct from 'false'
     or v_reclaim ->> 'reason' is distinct from 'revision_conflict' then
    raise exception 'stale revision unexpectedly reclaimed a submission slot';
  end if;
  v_reclaim := public.update_bulk_operation(
    'bulk-tag',
    jsonb_set(v_reset -> 'operation', '{external_job,phase}', '"submitting"'::jsonb),
    'running', 2, 'worker-B', 120);
  v_new_token := v_reclaim ->> 'lease_token';
  if v_reclaim ->> 'ok' is distinct from 'true'
     or v_reclaim ->> 'lease_receipt_issued' is distinct from 'true'
     or v_new_token is null or v_new_token = v_token then
    raise exception 'fresh revision did not receive its own one-time receipt';
  end if;
  perform pg_temp.expect_lease_reset_refusal(
    3, 'worker-B', v_token, 'provider_definitive_rejection', 400, v_error, '55000');

  -- An ordinary parsed validation failure remains usable after the stricter
  -- status gate; the current holder's new receipt can reset its own revision.
  v_reset := public.reset_bulk_operation_submission_lease(
    'bulk-tag', 3, 'worker-B', v_new_token,
    'provider_definitive_rejection', 422, v_error);
  if v_reset ->> 'ok' is distinct from 'true'
     or (v_reset ->> 'state_revision')::bigint is distinct from 4
     or (v_reset -> 'operation' -> 'external_job' ->> 'last_definitive_rejection_status')::integer
        is distinct from 422 then
    raise exception 'parsed final 422 rejection was not safely reset';
  end if;

  if has_function_privilege('anon',
       'public.reset_bulk_operation_submission_lease(text,bigint,text,text,text,integer,jsonb)',
       'EXECUTE') then
    raise exception 'anon must not execute the reset contract';
  end if;
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(p.proacl) a
    where p.oid = 'public.reset_bulk_operation_submission_lease(text,bigint,text,text,text,integer,jsonb)'::regprocedure
      and a.grantee = 0 and a.privilege_type = 'EXECUTE'
  ) then
    raise exception 'PUBLIC must not execute the reset contract';
  end if;
  if not has_function_privilege('authenticated',
       'public.reset_bulk_operation_submission_lease(text,bigint,text,text,text,integer,jsonb)',
       'EXECUTE') then
    raise exception 'authenticated worker lost reset execution privilege';
  end if;
end;
$test$;

rollback;
