-- derived-from: none
-- CRM admin settings RPCs (issue #4811).
--
-- popcrm-web gains an admin Settings area: designate salespeople and other
-- roles, manage per-app access and user status, bulk-assign customers to a
-- salesperson or account owner, and read an access-change history. The
-- browser cannot read the `app` schema, so every operation is an `api`
-- security-definer function hard-gated to administrators, modelled on
-- api.crm_admin_user_list (20260715184500).
--
-- Additive only: seven new functions plus an idempotent insert that ensures an
-- app.role row exists for every app.app_role enum value. Nothing is renamed or
-- dropped.

-- 0. One app.role row per app.app_role value (no-op where rows already exist).
insert into app.role (slug, name)
select e.slug, initcap(e.slug::text)
from unnest(enum_range(null::app.app_role)) as e(slug)
on conflict (slug) do nothing;

-- 1. Role catalogue.
create or replace function api.crm_admin_role_list()
returns jsonb
language plpgsql
stable
security definer
set search_path = app, public
as $$
declare
  result jsonb;
begin
  if not coalesce(app.has_role('administrator'), false) then
    raise exception 'crm: not authorized' using errcode = 'insufficient_privilege';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'slug', r.slug::text,
           'name', r.name,
           'description', r.description
         ) order by r.slug::text), '[]'::jsonb)
  into result
  from app.role r;

  return result;
end;
$$;

revoke all on function api.crm_admin_role_list() from public, anon;
grant execute on function api.crm_admin_role_list() to authenticated;
comment on function api.crm_admin_role_list() is
  'Admin-only list of roles ({slug, name, description}) ordered by slug. Powers popcrm-web Settings.';

-- 2. Full user directory (every profile except deleted).
create or replace function api.crm_admin_user_directory()
returns jsonb
language plpgsql
stable
security definer
set search_path = app, public
as $$
declare
  result jsonb;
begin
  if not coalesce(app.has_role('administrator'), false) then
    raise exception 'crm: not authorized' using errcode = 'insufficient_privilege';
  end if;

  select coalesce(jsonb_agg(to_jsonb(u) order by lower(coalesce(u.display_name, u.email)), u.email), '[]'::jsonb)
  into result
  from (
    select
      p.id,
      p.email::text            as email,
      p.display_name,
      p.avatar_url,
      p.status::text           as status,
      p.created_at,
      au.last_sign_in_at,
      coalesce((
        select array_agg(r.slug::text order by r.slug::text)
        from app.user_role ur
        join app.role r on r.id = ur.role_id
        where ur.profile_id = p.id and ur.revoked_at is null
      ), array[]::text[])      as roles,
      coalesce((
        select array_agg(aa.app::text order by aa.app::text)
        from app.app_access aa
        where aa.profile_id = p.id and aa.revoked_at is null
      ), array[]::text[])      as apps,
      (
        exists (
          select 1 from app.app_access aa
          where aa.profile_id = p.id and aa.app = 'crm' and aa.revoked_at is null
        )
        or exists (
          select 1 from app.user_role ur
          join app.role r on r.id = ur.role_id
          where ur.profile_id = p.id and ur.revoked_at is null and r.slug = 'administrator'
        )
      )                        as crm_access,
      coalesce(sc.n, 0)        as salesperson_customer_count,
      coalesce(oc.n, 0)        as owner_customer_count
    from app.profile p
    left join auth.users au on au.id = p.auth_user_id
    left join (
      select c.primary_salesperson_profile_id as pid, count(*)::int as n
      from core.customer c
      where c.primary_salesperson_profile_id is not null
      group by 1
    ) sc on sc.pid = p.id
    left join (
      select c.account_owner_profile_id as pid, count(*)::int as n
      from core.customer c
      where c.account_owner_profile_id is not null
      group by 1
    ) oc on oc.pid = p.id
    where p.status <> 'deleted'
  ) u;

  return result;
end;
$$;

revoke all on function api.crm_admin_user_directory() from public, anon;
grant execute on function api.crm_admin_user_directory() to authenticated;
comment on function api.crm_admin_user_directory() is
  'Admin-only directory of all non-deleted profiles with last sign-in, active roles[], apps[], crm_access and customer assignment counts. Powers popcrm-web Settings.';

-- 3. Replace a user's active role set.
create or replace function api.crm_admin_set_user_roles(p_profile_id uuid, p_roles text[])
returns jsonb
language plpgsql
volatile
security definer
set search_path = app, public
as $$
declare
  v_actor uuid := app.current_profile_id();
  v_roles text[];
  v_unknown text[];
  v_role_ids uuid[];
begin
  if not coalesce(app.has_role('administrator'), false) then
    raise exception 'crm: not authorized' using errcode = 'insufficient_privilege';
  end if;

  if p_profile_id is null or not exists (
    select 1 from app.profile p where p.id = p_profile_id and p.status <> 'deleted'
  ) then
    raise exception 'crm: profile not found' using errcode = 'no_data_found';
  end if;

  if p_roles is null then
    raise exception 'crm: roles must not be null' using errcode = 'invalid_parameter_value';
  end if;

  select coalesce(array_agg(distinct x), array[]::text[]) into v_roles
  from unnest(p_roles) as t(x) where x is not null;

  select array_agg(x order by x) into v_unknown
  from unnest(v_roles) as t(x)
  where not exists (select 1 from app.role r where r.slug::text = x);
  if v_unknown is not null then
    raise exception 'crm: unknown role(s): %', array_to_string(v_unknown, ', ')
      using errcode = 'invalid_parameter_value';
  end if;

  if p_profile_id = v_actor and not ('administrator' = any(v_roles)) then
    raise exception 'crm: you cannot remove your own administrator role'
      using errcode = 'check_violation';
  end if;

  -- Serialize role and status changes so the last-administrator check
  -- cannot race (same lock key as crm_admin_set_user_status).
  perform pg_advisory_xact_lock(hashtext('api.crm_admin_access_invariant'));

  select coalesce(array_agg(r.id), array[]::uuid[]) into v_role_ids
  from app.role r where r.slug::text = any(v_roles);

  update app.user_role ur
     set revoked_at = now()
   where ur.profile_id = p_profile_id
     and ur.revoked_at is null
     and not (ur.role_id = any(v_role_ids));

  insert into app.user_role (profile_id, role_id, granted_by_profile_id, granted_at, revoked_at)
  select p_profile_id, rid, v_actor, now(), null
  from unnest(v_role_ids) as t(rid)
  on conflict (profile_id, role_id) do update
    set revoked_at = null,
        granted_at = now(),
        granted_by_profile_id = excluded.granted_by_profile_id
    where app.user_role.revoked_at is not null;

  if not exists (
    select 1 from app.user_role ur
    join app.role r on r.id = ur.role_id
    join app.profile p on p.id = ur.profile_id
    where r.slug = 'administrator' and ur.revoked_at is null and p.status = 'active'
  ) then
    raise exception 'crm: at least one active administrator is required'
      using errcode = 'check_violation';
  end if;

  return (select e from jsonb_array_elements(api.crm_admin_user_directory()) e
          where e->>'id' = p_profile_id::text);
end;
$$;

revoke all on function api.crm_admin_set_user_roles(uuid, text[]) from public, anon;
grant execute on function api.crm_admin_set_user_roles(uuid, text[]) to authenticated;
comment on function api.crm_admin_set_user_roles(uuid, text[]) is
  'Admin-only: make a user''s active roles exactly p_roles (soft grant/revoke on app.user_role). Rejects unknown slugs, removing your own administrator role, and leaving zero active administrators. Returns the user''s directory object.';

-- 4. Grant or revoke one app for a user.
create or replace function api.crm_admin_set_app_access(p_profile_id uuid, p_app text, p_enabled boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = app, public
as $$
declare
  v_actor uuid := app.current_profile_id();
  v_app app.app_name;
begin
  if not coalesce(app.has_role('administrator'), false) then
    raise exception 'crm: not authorized' using errcode = 'insufficient_privilege';
  end if;

  if p_profile_id is null or not exists (
    select 1 from app.profile p where p.id = p_profile_id and p.status <> 'deleted'
  ) then
    raise exception 'crm: profile not found' using errcode = 'no_data_found';
  end if;

  if p_enabled is null or p_app is null
     or not (p_app = any(enum_range(null::app.app_name)::text[])) then
    raise exception 'crm: unknown app or missing flag: %', coalesce(p_app, '<null>')
      using errcode = 'invalid_parameter_value';
  end if;
  v_app := p_app::app.app_name;

  if p_profile_id = v_actor and v_app = 'crm' and not p_enabled then
    raise exception 'crm: you cannot remove your own CRM access'
      using errcode = 'check_violation';
  end if;

  if p_enabled then
    insert into app.app_access (profile_id, app, granted_by_profile_id, granted_at, revoked_at)
    values (p_profile_id, v_app, v_actor, now(), null)
    on conflict (profile_id, app) do update
      set revoked_at = null,
          granted_at = now(),
          granted_by_profile_id = excluded.granted_by_profile_id
      where app.app_access.revoked_at is not null;
  else
    update app.app_access aa
       set revoked_at = now()
     where aa.profile_id = p_profile_id and aa.app = v_app and aa.revoked_at is null;
  end if;

  return (select e from jsonb_array_elements(api.crm_admin_user_directory()) e
          where e->>'id' = p_profile_id::text);
end;
$$;

revoke all on function api.crm_admin_set_app_access(uuid, text, boolean) from public, anon;
grant execute on function api.crm_admin_set_app_access(uuid, text, boolean) to authenticated;
comment on function api.crm_admin_set_app_access(uuid, text, boolean) is
  'Admin-only: grant or revoke one app (soft grant/revoke on app.app_access). You cannot remove your own CRM access. Returns the user''s directory object.';

-- 5. Activate or deactivate a user.
create or replace function api.crm_admin_set_user_status(p_profile_id uuid, p_status text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = app, public
as $$
begin
  if not coalesce(app.has_role('administrator'), false) then
    raise exception 'crm: not authorized' using errcode = 'insufficient_privilege';
  end if;

  if p_status is null or p_status not in ('active', 'inactive') then
    raise exception 'crm: status must be active or inactive'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_profile_id is null or not exists (
    select 1 from app.profile p where p.id = p_profile_id and p.status <> 'deleted'
  ) then
    raise exception 'crm: profile not found' using errcode = 'no_data_found';
  end if;

  if p_profile_id = app.current_profile_id() and p_status <> 'active' then
    raise exception 'crm: you cannot deactivate yourself'
      using errcode = 'check_violation';
  end if;

  -- Only active <-> inactive transitions; archived/potential are not managed here.
  if not exists (
    select 1 from app.profile p
    where p.id = p_profile_id and p.status in ('active', 'inactive')
  ) then
    raise exception 'crm: only active or inactive users can change status here'
      using errcode = 'check_violation';
  end if;

  perform pg_advisory_xact_lock(hashtext('api.crm_admin_access_invariant'));

  update app.profile p
     set status = p_status::app.entity_status
   where p.id = p_profile_id;

  if not exists (
    select 1 from app.user_role ur
    join app.role r on r.id = ur.role_id
    join app.profile p on p.id = ur.profile_id
    where r.slug = 'administrator' and ur.revoked_at is null and p.status = 'active'
  ) then
    raise exception 'crm: at least one active administrator is required'
      using errcode = 'check_violation';
  end if;

  return (select e from jsonb_array_elements(api.crm_admin_user_directory()) e
          where e->>'id' = p_profile_id::text);
end;
$$;

revoke all on function api.crm_admin_set_user_status(uuid, text) from public, anon;
grant execute on function api.crm_admin_set_user_status(uuid, text) to authenticated;
comment on function api.crm_admin_set_user_status(uuid, text) is
  'Admin-only: switch a user between active and inactive. You cannot deactivate yourself or the last active administrator. Returns the user''s directory object.';

-- 6. Bulk-assign customers to a salesperson or account owner (null unassigns).
create or replace function api.crm_admin_assign_customers(p_customer_ids uuid[], p_profile_id uuid, p_field text)
returns integer
language plpgsql
volatile
security definer
set search_path = app, public
as $$
declare
  v_count integer;
begin
  if not coalesce(app.has_role('administrator'), false) then
    raise exception 'crm: not authorized' using errcode = 'insufficient_privilege';
  end if;

  if p_field is null or p_field not in ('salesperson', 'account_owner') then
    raise exception 'crm: field must be salesperson or account_owner'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_profile_id is not null and not exists (
    select 1 from app.profile p where p.id = p_profile_id and p.status <> 'deleted'
  ) then
    raise exception 'crm: profile not found' using errcode = 'no_data_found';
  end if;

  if p_customer_ids is null or cardinality(p_customer_ids) = 0 then
    return 0;
  end if;

  if p_field = 'salesperson' then
    update core.customer c
       set primary_salesperson_profile_id = p_profile_id,
           updated_at = now()
     where c.id = any(p_customer_ids);
  else
    update core.customer c
       set account_owner_profile_id = p_profile_id,
           updated_at = now()
     where c.id = any(p_customer_ids);
  end if;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function api.crm_admin_assign_customers(uuid[], uuid, text) from public, anon;
grant execute on function api.crm_admin_assign_customers(uuid[], uuid, text) to authenticated;
comment on function api.crm_admin_assign_customers(uuid[], uuid, text) is
  'Admin-only: set core.customer primary salesperson (p_field=salesperson) or account owner (p_field=account_owner) for the given customers; null profile unassigns. Unknown customer ids are skipped; any non-deleted profile may be named. Returns rows updated.';

-- 7. Role and app grant/revoke history, newest first.
--    Derived from the current granted_at/revoked_at columns: a re-grant
--    overwrites the earlier grant time, and revocations carry no actor.
create or replace function api.crm_admin_access_history(p_limit integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path = app, public
as $$
declare
  result jsonb;
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 1000);
begin
  if not coalesce(app.has_role('administrator'), false) then
    raise exception 'crm: not authorized' using errcode = 'insufficient_privilege';
  end if;

  with ev as (
    select ur.granted_at as at, 'role'::text as kind, 'granted'::text as action,
           r.slug::text as value, ur.profile_id, ur.granted_by_profile_id as actor_id
    from app.user_role ur join app.role r on r.id = ur.role_id
    union all
    select ur.revoked_at, 'role', 'revoked', r.slug::text, ur.profile_id, null::uuid
    from app.user_role ur join app.role r on r.id = ur.role_id
    where ur.revoked_at is not null
    union all
    select aa.granted_at, 'app', 'granted', aa.app::text, aa.profile_id, aa.granted_by_profile_id
    from app.app_access aa
    union all
    select aa.revoked_at, 'app', 'revoked', aa.app::text, aa.profile_id, null::uuid
    from app.app_access aa
    where aa.revoked_at is not null
  ), top as (
    select * from ev order by at desc nulls last, profile_id, kind, value, action limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'at', t.at,
           'kind', t.kind,
           'action', t.action,
           'value', t.value,
           'profile_id', t.profile_id,
           'profile_name', coalesce(p.display_name, p.email::text),
           'actor_name', coalesce(a.display_name, a.email::text)
         ) order by t.at desc nulls last, t.profile_id, t.kind, t.value, t.action), '[]'::jsonb)
  into result
  from top t
  left join app.profile p on p.id = t.profile_id
  left join app.profile a on a.id = t.actor_id;

  return result;
end;
$$;

revoke all on function api.crm_admin_access_history(integer) from public, anon;
grant execute on function api.crm_admin_access_history(integer) to authenticated;
comment on function api.crm_admin_access_history(integer) is
  'Admin-only: newest-first role/app grant and revoke events ({at, kind, action, value, profile_id, profile_name, actor_name}) derived from app.user_role and app.app_access. A re-grant overwrites the earlier grant time; revocations have no recorded actor. p_limit clamped to 1..1000.';
