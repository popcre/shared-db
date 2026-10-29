-- Issue #5020 (claim #5021): Core Product Type storage for DesignFlow —
-- PRODUCTION HALF of the matched pair (schema `dflow_prod`, project
-- qsllyeztdwjgirsysgai). The sandbox half is version 20261029043759
-- (schema `dflow`, project xupnyeifmpsacrqahwwm).
-- Work issue popcre/designflow-item-master#150; plan plan_core-product-type.md
-- (branch sandbox-albert). Owner answers (Albert Hazan, 2026-10-29) are Settled
-- in docs/business-rules/merchandise-and-product-taxonomy.md.
--
-- The pair exists because this project ALSO carries a stale `dflow` schema
-- (legacy copy, not read by any item service since the 2026-10 Supabase
-- cutover): schema-existence conditioning inside one file cannot be both
-- correct and static, so each half is fail-loud about the project it must
-- never run on and each project's lane allowlists only its own half.
--
-- Objects (this file): dflow_prod.mg_combination_description (+_history),
-- dflow_prod.item_product_description (+_history), functions
-- dflow_prod.product_description_row_audit() and
-- dflow_prod.item_product_description_protect_human_override(), three
-- triggers, four indexes, grants to designflow_prod_item_master_grants.
--
-- Grants follow the item-master grants role on itemHeader
-- (designflow_prod_item_master_grants: INSERT, SELECT live there today) plus
-- the write verbs the feature needs: UPDATE for the human-override PATCH and
-- DELETE for run_id-scoped backfill rollback, on the live tables, and INSERT
-- on both history tables for the audit trigger.
--
-- Key shapes verified live 2026-10-29: itemHeader PK item_id_pk integer;
-- core."merchGroup" PK mg_id integer; udf_merchgroup0N_id integer.
--
-- Human override contract: a session may create, change or clear a human
-- override only after set_config('app.product_description.human','on',true)
-- in the same transaction (the item-master PATCH does this). Bulk/refresh
-- connections never set it, so the trigger fires for them.
--
-- Idempotent: IF NOT EXISTS / OR REPLACE / drop-if-exists; re-apply is a
-- no-op. Rollback: drop trigger item_product_description_write_guard on
-- dflow_prod.item_product_description and trigger product_description_audit
-- on both tables, drop function
-- dflow_prod.item_product_description_protect_human_override, drop function
-- dflow_prod.product_description_row_audit, drop table
-- dflow_prod.item_product_description_history,
-- dflow_prod.item_product_description,
-- dflow_prod.mg_combination_description_history,
-- dflow_prod.mg_combination_description.

set lock_timeout = '5s';
set statement_timeout = '2min';

do $$
begin
  if to_regnamespace('dflow_prod') is null then
    raise exception '#5020/20261029054534 self-check: schema dflow_prod is missing — wrong database for the production half (the sandbox half 20261029043759 applies on the sandbox project)'
      using errcode = 'feature_not_supported';
  end if;
  if to_regclass('core."merchGroup"') is null then
    raise exception '#5020/20261029054534 self-check: core."merchGroup" is missing — cannot create the combination FKs'
      using errcode = 'feature_not_supported';
  end if;
  if to_regclass('dflow_prod."itemHeader"') is null then
    raise exception '#5020/20261029054534 self-check: dflow_prod."itemHeader" is missing — wrong database'
      using errcode = 'feature_not_supported';
  end if;
end $$;

-- Combination table: one row per MG01+MG02+MG03 with its verified state and provenance.
create table if not exists dflow_prod.mg_combination_description (
  id bigint generated always as identity primary key,
  mg01_id integer not null references core."merchGroup"(mg_id),
  mg02_id integer not null references core."merchGroup"(mg_id),
  mg03_id integer not null references core."merchGroup"(mg_id),
  description text,
  status text not null default 'pending'
    constraint mg_combination_description_status_check
    check (status in ('published','failed','pending','review')),
  item_count integer,
  verified_count integer,
  verified_rate numeric(5,4),
  source_desc_sha256 text,
  engine_version text,
  run_id text,
  generated_at timestamptz not null default now(),
  constraint mg_combination_description_unique
    unique (mg01_id, mg02_id, mg03_id)
);

create table if not exists dflow_prod.mg_combination_description_history (
  history_id bigint generated always as identity primary key,
  history_at timestamptz not null default now(),
  like dflow_prod.mg_combination_description including defaults
);

-- Per-item copy: description, provenance and the never-machine-overwritten flag.
create table if not exists dflow_prod.item_product_description (
  item_fk integer primary key
    references dflow_prod."itemHeader"(item_id_pk) on delete cascade,
  combination_fk bigint references dflow_prod.mg_combination_description(id),
  description text,
  source text
    constraint item_product_description_source_check
    check (source in ('combination','human')),
  verified boolean,
  verify_score numeric(4,3),
  is_human_override boolean not null default false,
  override_user_fk integer,
  override_at timestamptz,
  run_id text,
  computed_at timestamptz not null default now(),
  constraint item_product_description_override_source_check
    check (not is_human_override or source = 'human')
);

create table if not exists dflow_prod.item_product_description_history (
  history_id bigint generated always as identity primary key,
  history_at timestamptz not null default now(),
  like dflow_prod.item_product_description including defaults
);

-- Audit: every UPDATE/DELETE copies the OLD row into the matching history table.
create or replace function dflow_prod.product_description_row_audit() returns trigger as $fn$
declare
  cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into cols
  from information_schema.columns
  where table_schema = tg_table_schema
    and table_name = tg_table_name;
  execute format('insert into %I.%I (%s) select $1.*',
    tg_table_schema, tg_table_name || '_history', cols)
    using old;
  return null;
end
$fn$ language plpgsql;

drop trigger if exists product_description_audit on dflow_prod.mg_combination_description;
create trigger product_description_audit
  after update or delete on dflow_prod.mg_combination_description
  for each row execute function dflow_prod.product_description_row_audit();

drop trigger if exists product_description_audit on dflow_prod.item_product_description;
create trigger product_description_audit
  after update or delete on dflow_prod.item_product_description
  for each row execute function dflow_prod.product_description_row_audit();

-- Guard: a human override is never created, changed or cleared by a machine
-- connection — only by a session that set app.product_description.human.
create or replace function dflow_prod.item_product_description_protect_human_override() returns trigger as $fn$
begin
  if coalesce(current_setting('app.product_description.human', true), '') = ''
    and (
      (old.is_human_override
        and (new.description is distinct from old.description
             or new.is_human_override is distinct from old.is_human_override))
      or (not old.is_human_override and new.is_human_override)
    )
  then
    raise exception 'item_product_description % carries or claims a human override; only a human session may set, change or clear it (set app.product_description.human in the transaction)',
      old.item_fk using errcode = 'check_violation';
  end if;
  return new;
end
$fn$ language plpgsql;

drop trigger if exists item_product_description_write_guard on dflow_prod.item_product_description;
create trigger item_product_description_write_guard
  before update on dflow_prod.item_product_description
  for each row execute function dflow_prod.item_product_description_protect_human_override();

-- Review list and run-scoped rollback support.
create index if not exists item_product_description_combination_idx
  on dflow_prod.item_product_description (combination_fk);

create index if not exists item_product_description_review_idx
  on dflow_prod.item_product_description (item_fk) where description is null;

create index if not exists item_product_description_run_idx
  on dflow_prod.item_product_description (run_id);

create index if not exists mg_combination_description_run_idx
  on dflow_prod.mg_combination_description (run_id);

grant select, insert, update, delete
  on dflow_prod.mg_combination_description,
    dflow_prod.mg_combination_description_history,
    dflow_prod.item_product_description,
    dflow_prod.item_product_description_history
  to designflow_prod_item_master_grants;
