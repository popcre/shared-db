-- =====================================================================================
-- Issue #4168 - PopSG NAS password: move out of plaintext admin_config into Supabase
-- Vault, readable only server-side (PopDAM u2giants/popdam3#194, browser exposure
-- already removed in popdam3 PR #313).
-- Claim #4181 reserves version 20261011170328 and exactly two objects:
--
--   function public.get_sg_nas_password()        (new)
--   function public.set_sg_nas_password(text)    (new)
--
-- derived-from: none
--
-- WHAT IT DOES
-- ---------------------------------------------------------------------------------
-- 1. Vault secret name 'popdam_sg_nas_password' becomes the single store for the
--    PopSG NAS password used by the Windows render agent.
-- 2. get_sg_nas_password() returns it ('' when unset); set_sg_nas_password(text)
--    creates or replaces it ('' or null clears it). Both are SECURITY DEFINER and
--    executable by service_role only (admin-api and agent-api edge functions).
--    Authenticated and anon clients cannot call them; vault.secrets is encrypted at
--    rest and not exposed through PostgREST.
-- 3. The current admin_config value (key WINDOWS_AGENT_SG_NAS_PASS) is copied into
--    Vault inside this migration; the value never leaves the database and is never
--    printed. The admin_config row is intentionally KEPT by this migration so the
--    currently deployed app keeps working; it is removed after popdam3 cuts over to
--    these functions (issue #4168 step 3, an application row cleanup).
-- =====================================================================================

create function public.get_sg_nas_password()
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    (select ds.decrypted_secret
       from vault.decrypted_secrets ds
      where ds.name = 'popdam_sg_nas_password'
      limit 1),
    '');
$function$;

create function public.set_sg_nas_password(p_password text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id uuid;
begin
  select s.id into v_id
    from vault.secrets s
   where s.name = 'popdam_sg_nas_password'
   limit 1;

  if v_id is null then
    perform vault.create_secret(
      coalesce(p_password, ''),
      'popdam_sg_nas_password',
      'PopSG NAS password for the PopDAM Windows render agent (shared-db#4168)');
  else
    perform vault.update_secret(v_id, coalesce(p_password, ''));
  end if;
end;
$function$;

revoke all on function public.get_sg_nas_password() from public;
revoke all on function public.get_sg_nas_password() from anon;
revoke all on function public.get_sg_nas_password() from authenticated;
grant execute on function public.get_sg_nas_password() to service_role;

revoke all on function public.set_sg_nas_password(text) from public;
revoke all on function public.set_sg_nas_password(text) from anon;
revoke all on function public.set_sg_nas_password(text) from authenticated;
grant execute on function public.set_sg_nas_password(text) to service_role;

comment on function public.get_sg_nas_password() is
  'shared-db#4168: PopSG NAS password from Vault secret popdam_sg_nas_password; service_role only.';
comment on function public.set_sg_nas_password(text) is
  'shared-db#4168: create/replace Vault secret popdam_sg_nas_password ('''' clears); service_role only.';

-- Copy the existing plaintext value into Vault, database-side only.
select public.set_sg_nas_password(ac.value #>> '{}')
  from public.admin_config ac
 where ac.key = 'WINDOWS_AGENT_SG_NAS_PASS'
   and jsonb_typeof(ac.value) = 'string'
   and not exists (select 1 from vault.secrets s where s.name = 'popdam_sg_nas_password');
