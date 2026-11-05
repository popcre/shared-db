-- Behavioural contract for migration 20261105225141 (#5776): read-only DesignFlow
-- user directory for The Oracle — view api.oracle_user_directory and role
-- oracle_directory_reader. Runs inside a transaction that rolls back.

do $catalog$
declare
  v_col text;
  v_priv text;
begin
  -- Role shape: NOLOGIN and nothing but the one SELECT.
  if not exists (select 1 from pg_roles where rolname = 'oracle_directory_reader') then
    raise exception 'oracle_directory_reader is missing';
  end if;
  if exists (select 1 from pg_roles where rolname = 'oracle_directory_reader'
             and (rolcanlogin or rolsuper or rolcreatedb or rolcreaterole or rolreplication)) then
    raise exception 'oracle_directory_reader has an unexpected role attribute';
  end if;

  if to_regclass('api.oracle_user_directory') is null then
    raise exception 'api.oracle_user_directory is missing';
  end if;

  if not has_table_privilege('oracle_directory_reader', 'api.oracle_user_directory', 'SELECT') then
    raise exception 'oracle_directory_reader cannot read api.oracle_user_directory';
  end if;
  foreach v_priv in array array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
    if has_table_privilege('oracle_directory_reader', 'api.oracle_user_directory', v_priv) then
      raise exception 'oracle_directory_reader holds % on api.oracle_user_directory', v_priv;
    end if;
  end loop;

  -- Browser roles and the service role must not see the company directory.
  foreach v_priv in array array['anon', 'authenticated', 'service_role', 'public'] loop
    if has_table_privilege(v_priv, 'api.oracle_user_directory', 'SELECT') then
      raise exception '% can read api.oracle_user_directory', v_priv;
    end if;
  end loop;

  -- No direct reach into dflow_prod — the legacy passw column included.
  if has_schema_privilege('oracle_directory_reader', 'dflow_prod', 'USAGE') then
    raise exception 'oracle_directory_reader has USAGE on dflow_prod';
  end if;
  if has_column_privilege('oracle_directory_reader', 'dflow_prod.users', 'passw', 'SELECT') then
    raise exception 'oracle_directory_reader can read dflow_prod.users.passw';
  end if;
  if has_schema_privilege('oracle_directory_reader', 'api', 'CREATE') then
    raise exception 'oracle_directory_reader can CREATE in api';
  end if;

  -- Projection shape: the safe identity columns plus role names, nothing else.
  foreach v_col in array array['user_id', 'email', 'name', 'lastname', 'status', 'level', 'office_location', 'roles'] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'api' and table_name = 'oracle_user_directory'
        and column_name = v_col
    ) then
      raise exception 'api.oracle_user_directory is missing column %', v_col;
    end if;
  end loop;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'api' and table_name = 'oracle_user_directory'
      and column_name not in ('user_id', 'email', 'name', 'lastname', 'status', 'level', 'office_location', 'roles')
  ) then
    raise exception 'api.oracle_user_directory exposes an undeclared column';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'api' and table_name = 'oracle_user_directory'
      and column_name = 'roles' and data_type = 'ARRAY'
  ) then
    raise exception 'api.oracle_user_directory.roles must be an array';
  end if;
end
$catalog$;

-- Live read as the role. The CI session user created the role and holds ADMIN
-- on it; this grant is test-only and rolls back.
grant oracle_directory_reader to postgres;
set local role oracle_directory_reader;

select user_id, email, name, lastname, status, level, office_location, roles
from api.oracle_user_directory
limit 0;

select count(*) from api.oracle_user_directory;

do $deny$
begin
  begin
    insert into api.oracle_user_directory (user_id, email) values (-1, 'x');
    raise exception 'oracle_directory_reader was able to INSERT api.oracle_user_directory';
  exception when insufficient_privilege or read_only_sql_transaction or feature_not_supported or object_not_in_prerequisite_state then null;
  end;
end
$deny$;

reset role;
