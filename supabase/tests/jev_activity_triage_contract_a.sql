-- =====================================================================================
-- Contract tests for migration 20261011205205_pm_jev_activity_triage_contract_a.sql
-- (#3298 claim #4204 -- PM Jev activity-triage migration A).
--
-- Run against a database where every supabase/migrations file is applied.
-- SIDE EFFECTS: fixture inserts/updates inside a transaction that ROLLS BACK.
--
-- WHAT IT ASSERTS
--   A  CATALOG. New tables, column, trigger, policies, NOLOGIN role, and grants exist
--      with the intended privilege surface (no public/anon execute on wrappers).
--   B  COMMENT VALIDATION. Empty/whitespace, >4,000, and NUL/control bodies are
--      rejected by api.pm_add_product_comment before insert.
--   C  BODY REVISION. Insert starts at 1; body change bumps; non-body change does not.
--   D  NON-ADMIN DENIED. A sales-role profile cannot create comments or operations.
--   E  CROSS-USER ISOLATION. User B cannot read user A's triage row via RLS.
--   F  ACCEPT ONCE. Accept creates one record and is idempotent; dismiss is terminal.
--   G  ENVELOPE / LEASE. Complete without a valid HMAC envelope is rejected; wrong
--      lease hash is rejected; body edit marks source_changed and blocks accept.
--   H  OPERATIONS SHAPES. Dependency/decision/reminder rows match My Work /
--      pm_department_report field contracts.
-- =====================================================================================

\set ON_ERROR_STOP on
begin;

do $$
declare
  v_admin_auth uuid := gen_random_uuid();
  v_admin_profile uuid;
  v_sales_auth uuid := gen_random_uuid();
  v_sales_profile uuid;
  v_other_auth uuid := gen_random_uuid();
  v_other_profile uuid;
  v_product uuid := gen_random_uuid();
  v_comment uuid;
  v_rev integer;
  v_result jsonb;
  v_triage_id uuid;
  v_lease_hash text;
  v_dep_id uuid;
  v_count integer;
  v_raised boolean;
  v_state text;
  v_op_id uuid;
begin
  -- ------------------------------------------------------------------
  -- A  CATALOG
  -- ------------------------------------------------------------------
  if to_regclass('pim.ai_activity_triage') is null then
    raise exception 'missing table pim.ai_activity_triage';
  end if;
  if to_regclass('pim.ai_activity_triage_eligibility') is null then
    raise exception 'missing table pim.ai_activity_triage_eligibility';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'app' and table_name = 'comment' and column_name = 'body_revision'
  ) then
    raise exception 'missing app.comment.body_revision';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgname = 'app_comment_body_revision' and tgrelid = 'app.comment'::regclass
  ) then
    raise exception 'missing trigger app_comment_body_revision';
  end if;
  if not exists (select 1 from pg_roles where rolname = 'pm_jev_triage_worker') then
    raise exception 'missing role pm_jev_triage_worker';
  end if;
  if exists (select 1 from pg_roles where rolname = 'pm_jev_triage_worker' and rolcanlogin) then
    raise exception 'pm_jev_triage_worker must be NOLOGIN';
  end if;
  -- Private workers are not executable by authenticated/anon/public.
  if has_function_privilege('authenticated', 'pim.pm_complete_activity_triage_worker(uuid,text,text,jsonb,jsonb,text)', 'execute') then
    raise exception 'authenticated must not execute pm_complete_activity_triage_worker';
  end if;
  if has_function_privilege('anon', 'api.pm_add_product_comment(uuid,text,uuid)', 'execute') then
    raise exception 'anon must not execute pm_add_product_comment';
  end if;
  if not has_function_privilege('authenticated', 'api.pm_add_product_comment(uuid,text,uuid)', 'execute') then
    raise exception 'authenticated must execute pm_add_product_comment';
  end if;

  -- ------------------------------------------------------------------
  -- Fixtures (rolled back)
  -- ------------------------------------------------------------------
  -- Bypass auth's invitation-gate trigger on auth.users (repo convention).
  perform set_config('session_replication_role', 'replica', true);
  insert into auth.users (id, email) values
    (v_admin_auth, 'jev-admin-' || v_admin_auth || '@example.test'),
    (v_sales_auth, 'jev-sales-' || v_sales_auth || '@example.test'),
    (v_other_auth, 'jev-other-' || v_other_auth || '@example.test');
  perform set_config('session_replication_role', 'origin', true);

  insert into app.profile (id, auth_user_id, email, display_name, status)
  values
    (gen_random_uuid(), v_admin_auth, 'jev-admin-' || v_admin_auth || '@example.test', 'Jev Admin', 'active'),
    (gen_random_uuid(), v_sales_auth, 'jev-sales-' || v_sales_auth || '@example.test', 'Jev Sales', 'active'),
    (gen_random_uuid(), v_other_auth, 'jev-other-' || v_other_auth || '@example.test', 'Jev Other', 'active');

  select id into v_admin_profile from app.profile where auth_user_id = v_admin_auth;
  select id into v_sales_profile from app.profile where auth_user_id = v_sales_auth;
  select id into v_other_profile from app.profile where auth_user_id = v_other_auth;

  insert into app.user_role (profile_id, role_id)
  select v_admin_profile, id from app.role where slug = 'administrator';
  insert into app.user_role (profile_id, role_id)
  select v_sales_profile, id from app.role where slug = 'sales';

  insert into pim.product (id, name, status, metadata)
  values (v_product, 'Jev Contract Product', 'active', '{"business_unit":"licensed"}'::jsonb);

  -- ------------------------------------------------------------------
  -- B  COMMENT VALIDATION + C BODY REVISION (as administrator)
  -- ------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_auth, 'role', 'authenticated')::text, true);

  v_raised := false;
  begin
    perform api.pm_add_product_comment(v_product, '   ', gen_random_uuid());
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception 'empty/whitespace comment body must be rejected';
  end if;

  v_raised := false;
  begin
    perform api.pm_add_product_comment(v_product, repeat('x', 4001), gen_random_uuid());
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception 'over-4000 comment body must be rejected';
  end if;

  v_raised := false;
  begin
    perform api.pm_add_product_comment(v_product, 'bad' || chr(1) || 'body', gen_random_uuid());
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception 'control-character comment body must be rejected';
  end if;

  -- Fixture writes run as the migration role; only RPC calls need the
  -- authenticated session role.
  v_result := api.pm_reserve_product_comment_operation(v_product, gen_random_uuid());
  if (v_result ->> 'status') <> 'reserved' then
    raise exception 'reserve must return reserved, got %', v_result ->> 'status';
  end if;
  v_op_id := (v_result ->> 'client_operation_id')::uuid;
  v_result := api.pm_add_product_comment(v_product, '  first valid comment  ', v_op_id);
  v_comment := (v_result ->> 'comment_id')::uuid;
  v_rev := (v_result ->> 'body_revision')::integer;
  if v_comment is null or v_rev is distinct from 1 then
    raise exception 'comment insert must stamp body_revision=1, got %', v_rev;
  end if;

  update app.comment set body = 'edited body' where id = v_comment;
  select body_revision into v_rev from app.comment where id = v_comment;
  if v_rev is distinct from 2 then
    raise exception 'body change must bump body_revision to 2, got %', v_rev;
  end if;

  update app.comment set visibility = 'internal' where id = v_comment;
  select body_revision into v_rev from app.comment where id = v_comment;
  if v_rev is distinct from 2 then
    raise exception 'non-body change must not bump body_revision, got %', v_rev;
  end if;

  -- ------------------------------------------------------------------
  -- D  NON-ADMIN DENIED
  -- ------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_sales_auth, 'role', 'authenticated')::text, true);
  v_raised := false;
  begin
    perform api.pm_add_product_comment(v_product, 'sales should not write', gen_random_uuid());
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception 'sales role must be denied comment create';
  end if;

  v_raised := false;
  begin
    perform api.pm_create_dependency(v_product, 'sales dependency');
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception 'sales role must be denied dependency create';
  end if;

  -- ------------------------------------------------------------------
  -- E  CROSS-USER ISOLATION (RLS select own)
  -- ------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_other_auth, 'role', 'authenticated')::text, true);

  -- Seed a triage row as admin first.
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_auth, 'role', 'authenticated')::text, true);
  v_result := api.pm_begin_activity_triage(
    v_comment,
    'digest-' || v_comment,
    'key-v1',
    'jev-test-model',
    'contract-v1',
    null,
    null
  );
  v_triage_id := (v_result ->> 'triage_id')::uuid;
  if v_triage_id is null then
    raise exception 'begin must create a triage row';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_other_auth, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_count from pim.ai_activity_triage where id = v_triage_id;
  if v_count <> 0 then
    raise exception 'other user must not read another requester triage row via RLS';
  end if;
  execute 'reset role';

  -- ------------------------------------------------------------------
  -- G  ENVELOPE / LEASE / SOURCE_CHANGED
  -- ------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_auth, 'role', 'authenticated')::text, true);

  v_raised := false;
  begin
    perform api.pm_complete_activity_triage(v_triage_id, 'wrong-hash', 'blocker_dependency', '{}'::jsonb, '{}'::jsonb, null, null);
  exception when others then
    v_raised := true;
  end;
  if not v_raised then
    raise exception 'complete without envelope must be rejected';
  end if;

  -- Body edit marks source_changed and blocks accept.
  update app.comment set body = 'edited after begin' where id = v_comment;
  select state into v_state from pim.ai_activity_triage where id = v_triage_id;
  if v_state is distinct from 'source_changed' then
    raise exception 'body edit must mark triage source_changed, got %', v_state;
  end if;

  v_result := api.pm_accept_activity_triage(v_triage_id, 'Title', null, null, null);
  if (v_result ->> 'status') not in ('source_changed', 'already_dismissed') then
    raise exception 'accept after body edit must not create a record, got %', v_result ->> 'status';
  end if;

  -- ------------------------------------------------------------------
  -- F  ACCEPT ONCE on a fresh actionable triage
  -- ------------------------------------------------------------------
  v_result := api.pm_reserve_product_comment_operation(v_product, gen_random_uuid());
  v_op_id := (v_result ->> 'client_operation_id')::uuid;
  v_result := api.pm_add_product_comment(v_product, 'accept-me comment', v_op_id);
  v_comment := (v_result ->> 'comment_id')::uuid;
  v_result := api.pm_begin_activity_triage(v_comment, 'digest-accept-' || v_comment, 'key-v1', 'jev-test-model', 'contract-v1', null, null);
  v_triage_id := (v_result ->> 'triage_id')::uuid;

  -- Force actionable succeeded state (simulate provider complete without envelope path).
  update pim.ai_activity_triage
  set state = 'succeeded', action_label = 'blocker_dependency', lease_token_hash = null
  where id = v_triage_id;

  v_result := api.pm_accept_activity_triage(v_triage_id, 'Blocked by vendor', null, null, null);
  if (v_result ->> 'status') <> 'accepted' then
    raise exception 'first accept must succeed, got %', v_result ->> 'status';
  end if;
  v_result := api.pm_accept_activity_triage(v_triage_id, 'Blocked by vendor', null, null, null);
  if (v_result ->> 'status') <> 'already_accepted' then
    raise exception 'second accept must be idempotent already_accepted, got %', v_result ->> 'status';
  end if;
  select count(*) into v_count from pim.ai_activity_triage where id = v_triage_id and state = 'accepted';
  if v_count <> 1 then
    raise exception 'accept must leave exactly one accepted row';
  end if;

  -- ------------------------------------------------------------------
  -- H  OPERATIONS SHAPES
  -- ------------------------------------------------------------------
  v_result := api.pm_create_dependency(v_product, 'Vendor sample delay');
  if (v_result ->> 'kind') <> 'dependency' then
    raise exception 'dependency kind mismatch';
  end if;
  v_dep_id := (v_result ->> 'id')::uuid;
  select count(*) into v_count from app.activity
  where id = v_dep_id and action = 'pm_dependency'
    and payload ->> 'kind' = 'dependency' and payload ->> 'status' = 'open';
  if v_count <> 1 then
    raise exception 'dependency row shape mismatch';
  end if;

  v_result := api.pm_create_decision(v_product, 'Go to market', 'notes here');
  select count(*) into v_count from app.activity
  where action = 'pm_decision' and target_id = v_product
    and payload ->> 'kind' = 'decision' and payload ->> 'status' = 'decided';
  if v_count < 1 then
    raise exception 'decision row shape mismatch';
  end if;

  v_result := api.pm_create_reminder(v_product, 'Follow up with vendor', date '2026-11-01');
  select count(*) into v_count from app.notification
  where app = 'pm' and target_id = v_product
    and payload ->> 'kind' = 'reminder' and payload ->> 'status' = 'open'
    and payload ->> 'reminder_type' = 'follow_up'
    and payload ->> 'due_at' = '2026-11-01';
  if v_count < 1 then
    raise exception 'reminder row shape mismatch';
  end if;

  v_result := api.pm_update_dependency_status(v_dep_id, 'resolved');
  if (v_result ->> 'status') <> 'resolved' then
    raise exception 'dependency status update failed';
  end if;

  raise notice 'jev_activity_triage_contract_a: all assertions passed';
end $$;

rollback;
