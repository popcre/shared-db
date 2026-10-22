-- #4634: production counterpart of sandbox-only migration 20261021150012 (#4534).
-- Version reserved by claim #4635. Production target verified from popcre-core-prod.
-- derived-from: none
-- Same shape as sandbox; vendor_id deliberately has no FK because the application
-- validates the environment-specific vendor mapping. WeChat activation is out of scope.
-- Grant only backend SELECT/INSERT/UPDATE. Identity sequences require no USAGE grant.
-- No change to runtime roles, memberships, existing tables, or production Cloud Run.
-- Rollback: reviewed forward migration; preserve any identities rather than drop data.

set lock_timeout = '5s';
set statement_timeout = '2min';

create table if not exists dflow_prod.vendor_wechat_identity (
  id bigint generated always as identity primary key,
  wechat_key text not null unique,
  unionid text,
  openid text not null,
  nickname text,
  avatar_url text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'blocked')),
  vendor_id integer,
  decided_by_user_id integer,
  decided_at timestamptz,
  first_seen_at timestamptz not null default clock_timestamp(),
  last_login_at timestamptz,
  check (wechat_key = coalesce(unionid, 'openid:' || openid)),
  check (status <> 'approved' or vendor_id is not null)
);

comment on table dflow_prod.vendor_wechat_identity is
  'WeChat login identities for vendor users; pending until an admin links vendor_id and approves (#4634).';

revoke all on table dflow_prod.vendor_wechat_identity from public, anon, authenticated;
grant select, insert, update on table dflow_prod.vendor_wechat_identity
  to designflow_prod_backend_runtime;
