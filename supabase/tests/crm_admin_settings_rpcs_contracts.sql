-- Contract test for the CRM admin settings RPCs (migration 20261026154345, #4811).
-- All fixture changes roll back.
--
-- Proves, as real authenticated users (SET LOCAL role + JWT sub):
--   * a non-administrator is refused by all seven functions (insufficient_privilege);
--   * an administrator can list roles and the directory, replace a user's role set,
--     toggle app access, change status, bulk-assign customers, and read history;
--   * unknown roles/apps/statuses/fields are rejected, and an administrator cannot
--     remove their own administrator role, their own CRM access, or deactivate self.
begin;

do $$
declare
  v_admin_role uuid;
  v_a_profile uuid; v_a_auth uuid;
  v_b_profile uuid; v_b_auth uuid;
  v_customer uuid;
  v_obj jsonb;
  v_arr jsonb;
  v_n integer;
  v_refused boolean;
  v_call text;
begin
  select p.id, p.auth_user_id into v_a_profile, v_a_auth
  from app.profile p where p.status = 'active' and p.auth_user_id is not null
  order by p.created_at, p.id limit 1 offset 0;
  select p.id, p.auth_user_id into v_b_profile, v_b_auth
  from app.profile p where p.status = 'active' and p.auth_user_id is not null
  order by p.created_at, p.id limit 1 offset 1;
  if v_b_profile is null then
    raise exception 'fixture requires two active authenticated profiles';
  end if;

  select id into v_admin_role from app.role where slug = 'administrator';
  insert into app.user_role (profile_id, role_id) values (v_a_profile, v_admin_role)
  on conflict (profile_id, role_id) do update set revoked_at = null;
  update app.user_role set revoked_at = now()
   where profile_id = v_b_profile and revoked_at is null;
  insert into app.app_access (profile_id, app) values (v_b_profile, 'crm')
  on conflict (profile_id, app) do update set revoked_at = null;

  insert into core.customer (name, code, status)
  values ('ZZ CRM Admin Fixture ' || gen_random_uuid()::text,
          'ZZCRMADM' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10), 'active')
  returning id into v_customer;

  -- Non-administrator: every function refuses.
  perform set_config('request.jwt.claim.sub', v_b_auth::text, true);
  perform set_config('role', 'authenticated', true);
  foreach v_call in array array[
    'select api.crm_admin_role_list()',
    'select api.crm_admin_user_directory()',
    format('select api.crm_admin_set_user_roles(%L, array[''viewer''])', v_b_profile),
    format('select api.crm_admin_set_app_access(%L, ''crm'', true)', v_b_profile),
    format('select api.crm_admin_set_user_status(%L, ''active'')', v_b_profile),
    format('select api.crm_admin_assign_customers(array[%L]::uuid[], %L, ''salesperson'')', v_customer, v_b_profile),
    'select api.crm_admin_access_history(10)'
  ] loop
    v_refused := false;
    begin
      execute v_call;
    exception when insufficient_privilege then
      v_refused := true;
    end;
    if not v_refused then
      raise exception 'non-administrator was not refused: %', v_call;
    end if;
  end loop;

  -- Administrator.
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claim.sub', v_a_auth::text, true);
  perform set_config('role', 'authenticated', true);

  v_arr := api.crm_admin_role_list();
  if jsonb_array_length(v_arr) < 6
     or not v_arr @> '[{"slug":"sales"},{"slug":"administrator"}]'::jsonb
     or not (v_arr->0 ? 'name' and v_arr->0 ? 'description') then
    raise exception 'role list wrong: %', v_arr;
  end if;

  v_arr := api.crm_admin_user_directory();
  select e into v_obj from jsonb_array_elements(v_arr) e where e->>'id' = v_b_profile::text;
  if v_obj is null or not (v_obj ?& array['id','email','display_name','avatar_url','status',
       'created_at','last_sign_in_at','roles','apps','crm_access',
       'salesperson_customer_count','owner_customer_count']) then
    raise exception 'directory object wrong: %', v_obj;
  end if;
  if (v_obj->>'crm_access')::boolean is not true or v_obj->'roles' <> '[]'::jsonb then
    raise exception 'directory baseline wrong: %', v_obj;
  end if;

  v_obj := api.crm_admin_set_user_roles(v_b_profile, array['viewer','sales','sales']);
  if v_obj->'roles' <> '["sales","viewer"]'::jsonb then
    raise exception 'set roles wrong: %', v_obj;
  end if;
  v_obj := api.crm_admin_set_user_roles(v_b_profile, array['sales']);
  if v_obj->'roles' <> '["sales"]'::jsonb then
    raise exception 'role removal wrong: %', v_obj;
  end if;

  v_refused := false;
  begin
    perform api.crm_admin_set_user_roles(v_b_profile, array['bogus']);
  exception when invalid_parameter_value then v_refused := true;
  end;
  if not v_refused then raise exception 'unknown role accepted'; end if;

  v_refused := false;
  begin
    perform api.crm_admin_set_user_roles(v_a_profile, array['sales']);
  exception when check_violation then v_refused := true;
  end;
  if not v_refused then raise exception 'self administrator removal accepted'; end if;

  v_obj := api.crm_admin_set_app_access(v_b_profile, 'crm', false);
  if (v_obj->>'crm_access')::boolean or v_obj->'apps' @> '["crm"]'::jsonb then
    raise exception 'crm revoke wrong: %', v_obj;
  end if;
  v_obj := api.crm_admin_set_app_access(v_b_profile, 'crm', true);
  if not (v_obj->>'crm_access')::boolean then
    raise exception 'crm regrant wrong: %', v_obj;
  end if;

  v_refused := false;
  begin
    perform api.crm_admin_set_app_access(v_a_profile, 'crm', false);
  exception when check_violation then v_refused := true;
  end;
  if not v_refused then raise exception 'self crm removal accepted'; end if;

  v_refused := false;
  begin
    perform api.crm_admin_set_app_access(v_b_profile, 'nope', true);
  exception when invalid_parameter_value then v_refused := true;
  end;
  if not v_refused then raise exception 'unknown app accepted'; end if;

  v_obj := api.crm_admin_set_user_status(v_b_profile, 'inactive');
  if v_obj->>'status' <> 'inactive' then raise exception 'status wrong: %', v_obj; end if;
  v_obj := api.crm_admin_set_user_status(v_b_profile, 'active');

  v_refused := false;
  begin
    perform api.crm_admin_set_user_status(v_a_profile, 'inactive');
  exception when check_violation then v_refused := true;
  end;
  if not v_refused then raise exception 'self deactivation accepted'; end if;

  v_refused := false;
  begin
    perform api.crm_admin_set_user_status(v_b_profile, 'deleted');
  exception when invalid_parameter_value then v_refused := true;
  end;
  if not v_refused then raise exception 'deleted status accepted'; end if;

  v_n := api.crm_admin_assign_customers(array[v_customer], v_b_profile, 'salesperson');
  if v_n <> 1 then raise exception 'assign salesperson count %', v_n; end if;
  v_n := api.crm_admin_assign_customers(array[v_customer], v_b_profile, 'account_owner');
  if v_n <> 1 then raise exception 'assign owner count %', v_n; end if;
  select e into v_obj from jsonb_array_elements(api.crm_admin_user_directory()) e
   where e->>'id' = v_b_profile::text;
  if (v_obj->>'salesperson_customer_count')::int < 1 or (v_obj->>'owner_customer_count')::int < 1 then
    raise exception 'customer counts wrong: %', v_obj;
  end if;
  v_n := api.crm_admin_assign_customers(array[v_customer], null, 'salesperson');
  if v_n <> 1 then raise exception 'unassign count %', v_n; end if;

  v_refused := false;
  begin
    perform api.crm_admin_assign_customers(array[v_customer], v_b_profile, 'designer');
  exception when invalid_parameter_value then v_refused := true;
  end;
  if not v_refused then raise exception 'unknown field accepted'; end if;

  v_arr := api.crm_admin_access_history(500);
  if not v_arr @> jsonb_build_array(jsonb_build_object(
       'kind','role','action','granted','value','sales','profile_id', v_b_profile)) then
    raise exception 'history missing sales grant';
  end if;
  if not v_arr @> jsonb_build_array(jsonb_build_object(
       'kind','role','action','revoked','value','viewer','profile_id', v_b_profile)) then
    raise exception 'history missing viewer revoke';
  end if;

  perform set_config('role', 'postgres', true);
  raise notice 'crm_admin_settings_rpcs_contracts: PASS';
end;
$$;

rollback;
