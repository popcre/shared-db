-- =====================================================================================
-- PopDAM: grant `dam` app access to every POP Creations employee automatically.
--
-- Owner rule (Albert, verbatim): "every employee of POP creations should have popdam access?"
-- Tracking: u2giants/popdam3#185. On 2026-10-07 25 existing @popcre.com employees were
-- granted app.app_access(app='dam') by hand because the signup hook only granted 'crm',
-- so new employees hit 403 "DAM access is required" from public.require_dam_access().
--
-- This changes only the signup hook app.handle_new_auth_user(): after the existing 'crm'
-- grant, a @popcre.com email also gets 'dam'. Everything else in the function is unchanged.
-- No backfill: existing employees were provisioned on 2026-10-07 (see the issue).
-- =====================================================================================

create or replace function app.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = app, public
as $$
declare
  v_profile_id uuid;
  v_admin_role_id uuid;
  v_crm_app app.app_name := 'crm';
  v_dam_app app.app_name := 'dam';
begin
  -- Upsert profile (in case a pre-seeded profile exists with matching email)
  insert into app.profile (auth_user_id, email, display_name, provider, status)
  values (
    new.id,
    new.email::extensions.citext,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', new.email),
    new.raw_app_meta_data->>'provider',
    'active'
  )
  on conflict (auth_user_id) do update
    set email        = excluded.email,
        display_name = coalesce(excluded.display_name, app.profile.display_name),
        provider     = excluded.provider
  returning id into v_profile_id;

  -- Grant CRM access for everyone who logs in (single-app context; admins can revoke)
  insert into app.app_access (profile_id, app)
  values (v_profile_id, v_crm_app)
  on conflict (profile_id, app) do nothing;

  -- Every POP Creations employee gets PopDAM access (owner rule, u2giants/popdam3#185).
  -- `do nothing` keeps an admin's earlier revocation in place.
  if new.email ilike '%@popcre.com' then
    insert into app.app_access (profile_id, app)
    values (v_profile_id, v_dam_app)
    on conflict (profile_id, app) do nothing;
  end if;

  -- Grant administrator role to the owner email(s)
  if new.email ilike 'u2giants@gmail.com' or new.email ilike 'albert@popcre.com' then
    select id into v_admin_role_id from app.role where slug = 'administrator';
    if v_admin_role_id is not null then
      insert into app.user_role (profile_id, role_id)
      values (v_profile_id, v_admin_role_id)
      on conflict (profile_id, role_id) do nothing;
    end if;
  end if;

  return new;
end;
$$;

comment on function app.handle_new_auth_user() is
  'Auto-provisions app.profile + CRM app_access on first login, plus DAM app_access for @popcre.com employees. Grants administrator role to the owner emails (u2giants@gmail.com, albert@popcre.com).';
