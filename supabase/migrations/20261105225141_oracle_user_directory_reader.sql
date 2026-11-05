-- Issue #5776. Read-only DesignFlow user directory for The Oracle
-- (u2giants/theoracle): one view projecting safe identity columns plus held
-- role names, and one NOLOGIN read-only role that will hold the login
-- provisioned outside git.
-- derived-from: none
--
-- Owner request (Albert Hazan, 2026-11-05): The Oracle must see all the
-- company's users/employees from the DesignFlow app, because that app has the
-- roles already set up and he does not want to set people up in two places.
-- DesignFlow PLM stays the sole writer of dflow_prod.users / user_roles /
-- "Roles"; The Oracle mirrors them read-only into its own roster.
--
-- WHAT THIS CREATES.
--   * view api.oracle_user_directory — per-user rows with user_id, email,
--     name, lastname, status, level, office_location and the held role names
--     as text[]. The view owner reads the base tables, so the login role never
--     receives table grants. The legacy passw / notes / phonenum /
--     subscription / auditlog / photo columns on dflow_prod.users are NOT
--     exposed and cannot be reached by the new role.
--   * role oracle_directory_reader — NOLOGIN, SELECT on the view only.
--
-- PRIVILEGE HYGIENE. api.* relations are auto-granted to anon/authenticated/
-- service_role by that schema's default privileges, so the view is explicitly
-- revoked from public, anon, authenticated and service_role before the one
-- grant to oracle_directory_reader. Without that revoke the company directory
-- would be readable by every browser login on the shared project.
--
-- WRITES: no INSERT/UPDATE/DELETE/TRUNCATE anywhere. The role's grant set is
-- a single SELECT on a single view. statement_timeout 30s,
-- idle_in_transaction_session_timeout 60s, connection limit 3,
-- default_transaction_read_only = on (a convenience, not a privilege boundary).
-- The role is BYPASSRLS-free on purpose: it queries only the view, whose owner
-- does the reading.
--
-- PLAIN CREATE ROLE (no if-not-exists) on purpose: production was verified on
-- 2026-11-05 to hold no oracle_* role, and a pre-existing role with unknown
-- attributes must fail the apply rather than be silently adopted.
-- ROLLBACK (forward fix): drop view api.oracle_user_directory; then
-- drop role oracle_directory_reader;
--
-- LOGIN: the role is NOLOGIN here. Login and password are enabled afterwards
-- outside git; the password lives only in 1Password vibe_coding (same pattern
-- as poppim_readonly_jcortazar, issue #4836).

begin;
set lock_timeout = '5s';
set statement_timeout = '5min';

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'oracle_directory_reader') then
    raise exception 'ABORT #5776: role oracle_directory_reader already exists; refusing to adopt it';
  end if;
end $$;

create role oracle_directory_reader nologin noinherit nosuperuser nocreatedb nocreaterole noreplication connection limit 3;

comment on role oracle_directory_reader is
  'Issue #5776. Read-only login for The Oracle''s DesignFlow directory sync. SELECT on api.oracle_user_directory only; no dflow_prod table grants.';

alter role oracle_directory_reader set statement_timeout = '30s';
alter role oracle_directory_reader set idle_in_transaction_session_timeout = '60s';
alter role oracle_directory_reader set default_transaction_read_only = on;

grant usage on schema api to oracle_directory_reader;

create view api.oracle_user_directory as
select
  u.id as user_id,
  u.email::text as email,
  u.name::text as name,
  u.lastname::text as lastname,
  u.status::text as status,
  u.level::text as level,
  u.office_location::text as office_location,
  coalesce(
    array_agg(r."Name"::text order by r."Name") filter (where r."Id" is not null),
    '{}'::text[]
  ) as roles
from dflow_prod.users u
left join dflow_prod.user_roles ur on ur.user_id = u.id
left join dflow_prod."Roles" r on r."Id" = ur.role_id
group by u.id, u.email, u.name, u.lastname, u.status, u.level, u.office_location;

comment on view api.oracle_user_directory is
  'Issue #5776. Read-only company user directory for The Oracle: identity fields plus held DesignFlow role names from dflow_prod. Sole writer of the base tables is DesignFlow PLM.';

revoke all on api.oracle_user_directory from public, anon, authenticated, service_role;
grant select on api.oracle_user_directory to oracle_directory_reader;

commit;
