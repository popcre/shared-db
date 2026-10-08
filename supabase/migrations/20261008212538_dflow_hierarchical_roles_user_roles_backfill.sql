-- =====================================================================================
-- Issue #4106 (popcre/designflow-frontend#288 chunk 1 / #289) — DesignFlow
-- hierarchical role tree, user_roles membership, additive backfill.
--
-- Claim: #4107. Reserved version 20261008212538.
--
-- WHY: DesignFlow has six hardcoded roles and one `users.level` string. The owner
-- (Albert Hazan, 2026-10-08) locked a categorized tree (admin as super-role;
-- design / production / sales / vendors categories with named leaves), multi-
-- membership on leaves only, category→leaf inheritance, and this hard rule:
-- "nobody loses access they already have, unless you explicitly say so."
-- "i want no one to move."
--
-- ADDITIVE ONLY. Nobody is moved. Nobody loses access. `users.level` values are
-- never modified. Old RolePermissions rows are never deleted or rewritten.
--
-- Tree (exact names, including `trading co.`):
--   admin                          super
--   ├── design                     category
--   │   ├── creative designer      leaf
--   │   ├── technical designer     leaf
--   │   └── project manager        leaf
--   ├── production                 category
--   │   ├── sourcing               leaf
--   │   ├── production coordinator leaf
--   │   └── QC                     leaf
--   ├── sales                      category
--   │   ├── salesperson            leaf
--   │   └── sales assistant        leaf
--   └── vendors                    category
--       ├── factory                leaf
--       └── trading co.            leaf
--
-- Existing `dflow."Roles"` rows reused where the name already matches the tree
-- (admin → super; production / sales → category). Remaining legacy names
-- (designer, sourcing_manager) stay as leaves under their category so nothing
-- disappears. New names are inserted. People hold leaves only via `dflow.user_roles`.
--
-- Backfill from `lower(trim(users.level))`:
--   admin            → admin
--   designer         → creative designer + technical designer + project manager
--   production       → production coordinator + QC
--   sales            → salesperson + sales assistant
--   sourcing_manager → sourcing
--   vendor           → factory
-- Unknown / null / blank level values abort the migration (listed in the exception).
--
-- RolePermissions: `RoleId` may already target any `dflow."Roles"` row, so after
-- the seed it can reference a category OR a leaf. The `UserId` per-user override
-- path (Sample QC model) is untouched. Role-level rows (`UserId IS NULL`) are
-- copied onto the matching category (sourcing_manager → `sourcing` leaf). Per-user
-- rows are left in place and keep working through the override path.
--
-- Live production read 2026-10-08 ~5:30 PM EDT (qsllyeztdwjgirsysgai):
--   Roles: 5 rows (admin, sales, designer, production, sourcing_manager) — no vendor row.
--   users.level (52 users, 0 null/blank): admin 8, designer 21, production 11,
--     sales 8, sourcing_manager 4.
--   RolePermissions: 8 rows, ALL per-user (UserId set); 0 role-level rows; 0 orphans.
--
-- Not here: app-repo DDL, moving people, deleting `users.level`, production
-- promotion (shared-db workflow owns it).
-- =====================================================================================

-- derived-from: none

set lock_timeout = '5s';
set statement_timeout = '5min';

-- ------------------------------------------------------------------------------
-- 1. Fail-loud pre-checks (trust boundary: migration of access)
-- ------------------------------------------------------------------------------

do $$
declare
  orphan_ids text;
  unknown_levels text;
begin
  select string_agg(p."Id"::text, ', ' order by p."Id")
    into orphan_ids
  from dflow."RolePermissions" p
  left join dflow."Roles" r on r."Id" = p."RoleId"
  where p."RoleId" is not null
    and r."Id" is null;

  if orphan_ids is not null then
    raise exception 'ABORT: RolePermissions orphan RoleId rows: %', orphan_ids;
  end if;

  select string_agg(distinct label, ', ' order by label)
    into unknown_levels
  from (
    select coalesce(level, '<NULL>') as label
    from dflow.users
    where level is null
       or trim(level) = ''
       or lower(trim(level)) not in (
            'admin', 'designer', 'production', 'sales', 'sourcing_manager', 'vendor'
          )
  ) bad;

  if unknown_levels is not null then
    raise exception 'ABORT: unknown users.level values (normalize or map these first): %', unknown_levels;
  end if;
end
$$;

-- ------------------------------------------------------------------------------
-- 2. Roles tree shape (additive columns on the existing table)
-- ------------------------------------------------------------------------------

alter table dflow."Roles"
  add column if not exists kind text
    not null default 'leaf',
  add column if not exists parent_id integer,
  add column if not exists is_active boolean not null default true;

alter table dflow."Roles" drop constraint if exists roles_parent_id_fkey;
alter table dflow."Roles"
  add constraint roles_parent_id_fkey
  foreign key (parent_id)
  references dflow."Roles"("Id")
  on update cascade
  on delete set null;

alter table dflow."Roles" drop constraint if exists roles_kind_check;
alter table dflow."Roles"
  add constraint roles_kind_check
  check (kind in ('super', 'category', 'leaf'));

create unique index if not exists roles_name_uidx
  on dflow."Roles" ("Name");

comment on column dflow."Roles".kind is
  'Hierarchy node kind: super (admin, outside categories), category, or leaf. People hold leaves only.';
comment on column dflow."Roles".parent_id is
  'Parent role Id for category→leaf (and legacy leaf) hierarchy. NULL for super and category roots.';
comment on column dflow."Roles".is_active is
  'Soft retire flag. Default true. This migration never turns a role off.';

-- ------------------------------------------------------------------------------
-- 3. Classify existing rows, then seed the locked tree (exact names)
-- ------------------------------------------------------------------------------

-- Roots first (design and vendors are new; production / sales / admin already exist).
insert into dflow."Roles" ("Name", kind, parent_id, is_active)
values
  ('design',  'category', null, true),
  ('vendors', 'category', null, true)
on conflict ("Name") do update
  set kind = excluded.kind,
      is_active = excluded.is_active;

update dflow."Roles"
set kind = 'super',
    parent_id = null,
    is_active = true
where "Name" = 'admin';

update dflow."Roles"
set kind = 'category',
    parent_id = null,
    is_active = true
where "Name" in ('production', 'sales');

-- Legacy names that are not in the locked leaf set stay as leaves under their
-- category so no historical RolePermissions row loses its role.
update dflow."Roles" r
set kind = 'leaf',
    parent_id = c."Id",
    is_active = true
from dflow."Roles" c
where r."Name" = 'designer'
  and c."Name" = 'design';

update dflow."Roles" r
set kind = 'leaf',
    parent_id = c."Id",
    is_active = true
from dflow."Roles" c
where r."Name" = 'sourcing_manager'
  and c."Name" = 'production';

-- Locked leaves (exact strings — including `trading co.` and `QC`).
insert into dflow."Roles" ("Name", kind, parent_id, is_active)
select v.leaf_name, 'leaf', c."Id", true
from (
  values
    ('design',     'creative designer'),
    ('design',     'technical designer'),
    ('design',     'project manager'),
    ('production', 'sourcing'),
    ('production', 'production coordinator'),
    ('production', 'QC'),
    ('sales',      'salesperson'),
    ('sales',      'sales assistant'),
    ('vendors',    'factory'),
    ('vendors',    'trading co.')
) as v(category_name, leaf_name)
join dflow."Roles" c on c."Name" = v.category_name
on conflict ("Name") do update
  set kind = excluded.kind,
      parent_id = excluded.parent_id,
      is_active = excluded.is_active;

-- ------------------------------------------------------------------------------
-- 4. user_roles membership (people hold leaves / the admin super-role only)
-- ------------------------------------------------------------------------------

create table if not exists dflow.user_roles (
  user_id    integer not null references dflow.users(id) on delete cascade,
  role_id    integer not null references dflow."Roles"("Id") on delete cascade,
  granted_by integer references dflow.users(id),
  granted_at timestamptz not null default now(),
  primary key (user_id, role_id)
);

comment on table dflow.user_roles is
  'Multi-role membership. People hold leaf roles (and the admin super-role) only, never categories. Composite PK blocks duplicate grants.';
comment on column dflow.user_roles.granted_by is
  'User id of the grantor. NULL for the additive migration backfill.';

create index if not exists user_roles_role_id_idx
  on dflow.user_roles (role_id);

-- ------------------------------------------------------------------------------
-- 5. Backfill from users.level (case-normalized; values themselves untouched)
-- ------------------------------------------------------------------------------

insert into dflow.user_roles (user_id, role_id, granted_by, granted_at)
select u.id, r."Id", null, now()
from dflow.users u
join (
  values
    ('admin',            'admin'),
    ('designer',         'creative designer'),
    ('designer',         'technical designer'),
    ('designer',         'project manager'),
    ('production',       'production coordinator'),
    ('production',       'QC'),
    ('sales',            'salesperson'),
    ('sales',            'sales assistant'),
    ('sourcing_manager', 'sourcing'),
    ('vendor',           'factory')
) as map(old_level, leaf_name)
  on map.old_level = lower(trim(u.level))
join dflow."Roles" r on r."Name" = map.leaf_name
on conflict (user_id, role_id) do nothing;

-- ------------------------------------------------------------------------------
-- 6. Copy role-level RolePermissions onto categories (sourcing_manager → sourcing)
-- ------------------------------------------------------------------------------

-- Role-level rows only (`UserId IS NULL`). Per-user rows (Sample QC model) stay
-- on their existing row and keep working through the UserId override path —
-- copying those onto a category would hand the flag to everyone in the category.
insert into dflow."RolePermissions" ("RoleId", "UserId", "ElementId", "Access")
select target."Id", p."UserId", p."ElementId", p."Access"
from dflow."RolePermissions" p
join dflow."Roles" source on source."Id" = p."RoleId"
join dflow."Roles" target
  on target."Name" = case source."Name"
       when 'designer'         then 'design'
       when 'vendor'           then 'vendors'
       when 'sourcing_manager' then 'sourcing'
       when 'production'       then 'production'
       when 'sales'            then 'sales'
     end
where p."UserId" is null
  and target."Name" is distinct from source."Name"
on conflict ("RoleId", "UserId", "ElementId") do nothing;

-- production → production and sales → sales are name-identical: the existing
-- role-level rows already sit on the category row after the kind update above.
-- Nothing to copy. (Live 2026-10-08: zero role-level rows existed at all.)

-- ------------------------------------------------------------------------------
-- 7. Post-checks (the migration refuses to finish wrong)
-- ------------------------------------------------------------------------------

do $$
declare
  expected_admin int;
  actual_admin int;
  bad_tree text;
  bad_membership text;
begin
  select count(*) into expected_admin
  from dflow.users
  where lower(trim(level)) = 'admin';

  select count(*) into actual_admin
  from dflow.user_roles ur
  join dflow."Roles" r on r."Id" = ur.role_id
  where r."Name" = 'admin' and r.kind = 'super';

  if expected_admin <> actual_admin then
    raise exception 'ABORT: admin backfill count mismatch: users.level=admin %, user_roles admin grants %',
      expected_admin, actual_admin;
  end if;

  select string_agg(name, ', ' order by name)
    into bad_tree
  from (
    select r."Name" as name
    from dflow."Roles" r
    where r."Name" in (
      'admin', 'design', 'production', 'sales', 'vendors',
      'creative designer', 'technical designer', 'project manager',
      'sourcing', 'production coordinator', 'QC',
      'salesperson', 'sales assistant',
      'factory', 'trading co.'
    )
      and not (
        (r."Name" = 'admin' and r.kind = 'super' and r.parent_id is null)
        or (r."Name" in ('design', 'production', 'sales', 'vendors')
            and r.kind = 'category' and r.parent_id is null)
        or (r.kind = 'leaf' and r.parent_id is not null)
      )
  ) incomplete;

  if bad_tree is not null then
    raise exception 'ABORT: tree rows incomplete or mis-typed: %', bad_tree;
  end if;

  select string_agg(u.email, ', ' order by u.email)
    into bad_membership
  from dflow.user_roles ur
  join dflow."Roles" r on r."Id" = ur.role_id
  join dflow.users u on u.id = ur.user_id
  where r.kind = 'category';

  if bad_membership is not null then
    raise exception 'ABORT: membership on a category (people hold leaves only): %', bad_membership;
  end if;
end
$$;
