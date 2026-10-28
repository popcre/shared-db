-- =====================================================================================
-- Admin RPCs for the PopDAM user-management UI (per-user app-role picker).
-- Claim: popcre/shared-db#4949. Consumer: u2giants/popdam3#566.
--
-- Owner instruction (Albert, verbatim, 2026-10-27): "i want to be able to pick
-- roles on a user-by-user basis in the ui."
--
-- `app` tables are not PostgREST-exposed; `app.has_any_role` proves app-schema
-- RPCs are callable. These two SECURITY DEFINER functions give the admin
-- edge function (service client) a single reviewed read/write path for
-- `app.user_role` rows. Service-role-only: BOTH functions refuse every caller
-- that is not service_role (the admin-api enforces its own admin gate before
-- calling; the functions do not trust authenticated/anon callers).
--
-- Single-role contract: the UI picker picks exactly one role per user (or
-- none). Setting a role revokes the user's other active roles — the response
-- reports what was revoked so the UI can surface it.
-- =====================================================================================

create or replace function app.admin_list_user_app_roles()
returns table (
  auth_user_id uuid,
  email        text,
  display_name text,
  provider     text,
  status       app.entity_status,
  roles        app.app_role[]
)
language plpgsql
stable
security definer
set search_path = app, public
as $function$
begin
  if auth.role() is distinct from 'service_role' then
    raise insufficient_privilege using message = 'service role only';
  end if;

  return query
  select p.auth_user_id,
         p.email::text,
         p.display_name,
         p.provider,
         p.status,
         coalesce(array_agg(distinct r.slug) filter (where ur.revoked_at is null and r.slug is not null), '{}')
  from app.profile p
  left join app.user_role ur on ur.profile_id = p.id
  left join app.role r on r.id = ur.role_id
  where p.auth_user_id is not null
  group by p.auth_user_id, p.email, p.display_name, p.provider, p.status
  order by p.email;
end;
$function$;

create or replace function app.admin_set_user_app_role(
  p_auth_user uuid,
  p_role app.app_role,
  p_granted_by_auth uuid default null
)
returns table (roles app.app_role[], revoked app.app_role[])
language plpgsql
volatile
security definer
set search_path = app, public
as $function$
declare
  v_profile_id uuid;
  v_granter_id uuid;
  v_role_id uuid;
  v_revoked app.app_role[];
begin
  if auth.role() is distinct from 'service_role' then
    raise insufficient_privilege using message = 'service role only';
  end if;

  -- Serialize concurrent setters on the profile row and resolve the profile.
  select id into v_profile_id from app.profile
   where auth_user_id = p_auth_user for update;
  if v_profile_id is null then
    raise exception 'no profile for auth user %', p_auth_user using errcode = '22023';
  end if;

  -- Resolve the granter's own profile id server-side (the caller holds auth
  -- ids; granted_by_profile_id references app.profile(id) — 20260726210000:97-106
  -- is the precedent). A null/unknown granter records null attribution rather
  -- than failing the admin action.
  if p_granted_by_auth is not null then
    select id into v_granter_id from app.profile where auth_user_id = p_granted_by_auth;
  end if;

  -- Last-administrator guard: refuse to remove or replace the only active
  -- administrator role in the fleet.
  if p_role is distinct from 'administrator' and exists (
      select 1 from app.user_role ur join app.role r on r.id = ur.role_id
       where ur.profile_id = v_profile_id and ur.revoked_at is null
         and r.slug = 'administrator')
     and not exists (
      select 1 from app.user_role ur2 join app.role r2 on r2.id = ur2.role_id
       join app.profile p2 on p2.id = ur2.profile_id
       where ur2.revoked_at is null and r2.slug = 'administrator'
         and p2.status = 'active' and ur2.profile_id <> v_profile_id) then
    raise exception 'refusing to remove the only active administrator' using errcode = '22023';
  end if;

  -- Single-role replace: revoke every active role, remember what was revoked.
  select coalesce(array_agg(distinct r.slug), '{}') into v_revoked
    from app.user_role ur join app.role r on r.id = ur.role_id
   where ur.profile_id = v_profile_id and ur.revoked_at is null;

  update app.user_role
     set revoked_at = now()
   where profile_id = v_profile_id
     and revoked_at is null;

  if p_role is not null then
    select id into v_role_id from app.role where slug = p_role;
    if v_role_id is null then
      raise exception 'unknown app role: %', p_role using errcode = '22023';
    end if;

    -- Precedent form (20260726210000:117-120): reactivation clears revoked_at
    -- and bumps granted_at; original attribution is preserved, not rewritten.
    insert into app.user_role (profile_id, role_id, granted_by_profile_id, granted_at, revoked_at)
    values (v_profile_id, v_role_id, v_granter_id, now(), null)
    on conflict (profile_id, role_id) do update
       set revoked_at = null,
           granted_at = now()
       where app.user_role.revoked_at is not null;
  end if;

  return query
  select coalesce(array_agg(distinct r.slug) filter (where ur.revoked_at is null and r.slug is not null), '{}'),
         v_revoked
  from app.user_role ur join app.role r on r.id = ur.role_id
  where ur.profile_id = v_profile_id;
end;
$function$;

revoke all on function app.admin_list_user_app_roles() from public, authenticated, anon;
revoke all on function app.admin_set_user_app_role(uuid, app.app_role, uuid) from public, authenticated, anon;
grant execute on function app.admin_list_user_app_roles() to service_role;
grant execute on function app.admin_set_user_app_role(uuid, app.app_role, uuid) to service_role;

comment on function app.admin_list_user_app_roles() is
  'Service-role-only staff listing with active app roles (PopDAM admin UI, #4949/#566).';
comment on function app.admin_set_user_app_role(uuid, app.app_role, uuid) is
  'Service-role-only: replace a user''s active app role with exactly one (or none); returns the resulting roles and what was revoked; refuses to remove the only active administrator. PopDAM admin UI, #4949/#566.';
