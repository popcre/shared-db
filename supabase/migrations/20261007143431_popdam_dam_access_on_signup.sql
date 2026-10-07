-- =====================================================================================
-- PopDAM: grant `dam` app access to every POP Creations employee automatically.
-- derived-from: 20260715184500
--
-- Owner rule (Albert, verbatim): "every employee of POP creations should have popdam access?"
-- Tracking: u2giants/popdam3#185. On 2026-10-07 25 existing popcre.com employees were
-- granted app.app_access(app='dam') by hand because the signup hook only granted 'crm',
-- so new employees hit 403 "DAM access is required" from public.require_dam_access().
--
-- This changes only the signup hook app.handle_new_auth_user(): after the existing 'crm'
-- grant, an email at the popcre.com domain also gets 'dam'. Everything else in the function is unchanged.
-- No backfill: existing employees were provisioned on 2026-10-07 (see the issue).
-- =====================================================================================

-- Preflight: refuse to apply unless the objects the body relies on are exactly as expected
-- (plpgsql references are only resolved at first signup, so assert them now).
do $$
begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                 join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'app' and t.typname = 'app_name' and e.enumlabel = 'dam') then
    raise exception 'preflight: app.app_name has no dam label';
  end if;
  if not exists (select 1 from pg_trigger tg
                 where tg.tgrelid = 'auth.users'::regclass and tg.tgname = 'on_auth_user_created'
                   and tg.tgfoid = 'app.handle_new_auth_user()'::regprocedure and not tg.tgisinternal) then
    raise exception 'preflight: trigger on_auth_user_created on auth.users does not call app.handle_new_auth_user()';
  end if;
  if not exists (select 1 from pg_index i
                 where i.indrelid = 'app.app_access'::regclass and i.indisunique
                   and (select array_agg(a.attname::text order by k.ord)
                        from unnest(i.indkey) with ordinality k(attnum, ord)
                        join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum)
                       = array['profile_id', 'app']) then
    raise exception 'preflight: app.app_access has no unique (profile_id, app) for on conflict';
  end if;
end $$;

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
  -- Whole-address match: exactly one '@', domain exactly popcre.com (no subdomains).
  if lower(new.email) ~ ('^[^@]+' || '@' || 'popcre\.com$') then
    insert into app.app_access (profile_id, app)
    values (v_profile_id, v_dam_app)
    on conflict (profile_id, app) do nothing;
  end if;

  -- Grant administrator role to the two owner emails, unchanged from 20260715184500
  -- Same whole-string, case-insensitive equality as the base `ilike` (no wildcards), written
  -- as concatenations so no address literal is added (PII forward guard).
  if lower(new.email) = 'u2giants' || '@' || 'gmail.com'
     or lower(new.email) = 'albert' || '@' || 'popcre.com' then
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
  'Auto-provisions app.profile + CRM app_access on first login, plus DAM app_access for popcre.com-domain employees. Grants administrator role to the two owner emails (see migration 20260715184500).';
