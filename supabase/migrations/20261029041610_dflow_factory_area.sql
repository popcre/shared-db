-- DesignFlow factory area, #4708 / claim #4749
-- Owner rulings (Albert Hazan): 2026-10-25 "a factory record needs a party type
-- (factory vs trading company) and a link from a trading company to the
-- factories it represents; blank represented-by means POP deals directly";
-- 2026-10-25 future fields "orders completed" and "problem on order";
-- 2026-10-25 product categories from the owner's 22-category list;
-- 2026-10-27 the owner's review workbook is the truth (reps, logins, kept rows).
-- Structure only. The rows (kept factories, categories, reps, logins) are a
-- curated Master Data load from the owner's private workbook, not this file.

begin;

alter table core.factory
  add column if not exists party_type text
    constraint factory_party_type_check check (party_type in ('factory', 'trading_company', 'both')),
  add column if not exists designflow_vendor_id integer,
  add column if not exists trade_name text,
  add column if not exists orders_completed integer
    constraint factory_orders_completed_check check (orders_completed >= 0),
  add column if not exists orders_with_problem integer
    constraint factory_orders_with_problem_check check (orders_with_problem >= 0);

create unique index if not exists factory_designflow_vendor_id_key
  on core.factory (designflow_vendor_id) where designflow_vendor_id is not null;

comment on column core.factory.party_type is
  'Owner ruling 2026-10-25: factory, trading_company or both. Null = not reviewed.';
comment on column core.factory.designflow_vendor_id is
  'DesignFlow vendor id this factory was reviewed from (owner workbook 2026-10-27).';
comment on column core.factory.trade_name is 'Trade name the owner uses for this party.';
comment on column core.factory.orders_completed is 'Owner ruling 2026-10-25: orders completed. Empty until a source fills it.';
comment on column core.factory.orders_with_problem is 'Owner ruling 2026-10-25: orders with a problem. Empty until a source fills it.';

create table if not exists core.product_category (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table core.product_category is 'Owner product-category list (2026-10-25), used to tag factories.';

create table if not exists core.factory_product_category (
  factory_id uuid not null references core.factory(id) on delete cascade,
  product_category_id uuid not null references core.product_category(id) on delete restrict,
  rank smallint not null check (rank between 1 and 5),
  created_at timestamptz not null default now(),
  primary key (factory_id, product_category_id),
  unique (factory_id, rank)
);
comment on table core.factory_product_category is 'Up to five product categories per factory, in the owner''s order.';

create table if not exists core.factory_representation (
  trading_company_id uuid not null references core.factory(id) on delete cascade,
  factory_id uuid not null references core.factory(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (trading_company_id, factory_id),
  check (trading_company_id <> factory_id)
);
create index if not exists factory_representation_factory_idx on core.factory_representation (factory_id);
comment on table core.factory_representation is
  'Trading company -> factory it represents. No row = POP deals with the factory directly.';

create table if not exists core.factory_rep (
  id uuid primary key default gen_random_uuid(),
  factory_id uuid not null references core.factory(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (factory_id, name)
);
comment on table core.factory_rep is 'Named sales reps POP deals with at a factory.';

create table if not exists core.factory_vendor_login (
  designflow_login_id integer primary key,
  factory_id uuid not null references core.factory(id) on delete cascade,
  person text,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists factory_vendor_login_factory_idx on core.factory_vendor_login (factory_id);
comment on table core.factory_vendor_login is
  'DesignFlow vendor logins the owner kept (2026-10-27), and the factory each belongs to. Emails: administrators only.';

alter table core.product_category enable row level security;
revoke all on core.product_category from anon;
grant select, insert, update, delete on core.product_category to authenticated;
grant all on core.product_category to service_role;
create policy admin_write on core.product_category for all to authenticated
  using (app.has_role('administrator'::app.app_role)) with check (app.has_role('administrator'::app.app_role));

create policy shared_read on core.product_category for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

alter table core.factory_product_category enable row level security;
revoke all on core.factory_product_category from anon;
grant select, insert, update, delete on core.factory_product_category to authenticated;
grant all on core.factory_product_category to service_role;
create policy admin_write on core.factory_product_category for all to authenticated
  using (app.has_role('administrator'::app.app_role)) with check (app.has_role('administrator'::app.app_role));

create policy shared_read on core.factory_product_category for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

alter table core.factory_representation enable row level security;
revoke all on core.factory_representation from anon;
grant select, insert, update, delete on core.factory_representation to authenticated;
grant all on core.factory_representation to service_role;
create policy admin_write on core.factory_representation for all to authenticated
  using (app.has_role('administrator'::app.app_role)) with check (app.has_role('administrator'::app.app_role));

create policy shared_read on core.factory_representation for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

alter table core.factory_rep enable row level security;
revoke all on core.factory_rep from anon;
grant select, insert, update, delete on core.factory_rep to authenticated;
grant all on core.factory_rep to service_role;
create policy admin_write on core.factory_rep for all to authenticated
  using (app.has_role('administrator'::app.app_role)) with check (app.has_role('administrator'::app.app_role));

create policy shared_read on core.factory_rep for select to authenticated
  using (app.has_any_role(array['administrator','sales','licensing','designer','viewer','vendor']::app.app_role[]));

alter table core.factory_vendor_login enable row level security;
revoke all on core.factory_vendor_login from anon;
grant select, insert, update, delete on core.factory_vendor_login to authenticated;
grant all on core.factory_vendor_login to service_role;
create policy admin_write on core.factory_vendor_login for all to authenticated
  using (app.has_role('administrator'::app.app_role)) with check (app.has_role('administrator'::app.app_role));


drop trigger if exists set_updated_at on core.product_category;
create trigger set_updated_at before update on core.product_category
  for each row execute function app.set_updated_at();
drop trigger if exists set_updated_at on core.factory_rep;
create trigger set_updated_at before update on core.factory_rep
  for each row execute function app.set_updated_at();
drop trigger if exists set_updated_at on core.factory_vendor_login;
create trigger set_updated_at before update on core.factory_vendor_login
  for each row execute function app.set_updated_at();

commit;
