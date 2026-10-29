-- Issue #5020 (claim #5021): Core Product Type storage for DesignFlow.
-- Work issue: popcre/designflow-item-master#150; plan plan_core-product-type.md
-- (branch sandbox-albert). Owner answers (Albert Hazan, 2026-10-29) are Settled in
-- docs/business-rules/merchandise-and-product-taxonomy.md.
--
-- One description per MG01+MG02+MG03 combination, generated from ALL member item
-- descriptions; per-item copy with human-override protection. Two table pairs:
--   <s>.mg_combination_description      one row per combination (status/rates)
--   <s>.item_product_description        one row per item (item_id_pk PK)
-- plus *_history audit copies (UPDATE/DELETE trigger) and a trigger that rejects
-- machine updates of a human-override row.
--
-- Targets and conditioning (#2986 absent-schema conditioning):
--   - sandbox xupnyeifmpsacrqahwwm: schema `dflow` only (`dflow_prod` absent) ->
--     creates the `dflow` pair.
--   - production qsllyeztdwjgirsysgai: `dflow_prod` live (a stale `dflow` also
--     exists there, so schema existence alone cannot pick the arm; the presence of
--     `dflow_prod` does) -> creates the `dflow_prod` pair only.
--   - projects with neither schema (shared preview / shared production): the
--     version applies as a recorded no-op. Never allowlist this version to a
--   project where its arm would be wrong.
--
-- Key shapes verified live 2026-10-29: itemHeader PK item_id_pk integer;
-- core."merchGroup" PK mg_id integer; udf_merchgroup0N_id integer.
-- Sandbox runs its item service as the postgres pooler admin (no grant roles);
-- production grants follow the item-master grants role on itemHeader
-- (designflow_prod_item_master_grants) plus the write verbs the feature needs
-- (backfill delete by run_id, override update).
--
-- Human override contract: a session may change the description (or clear the
-- override) of an is_human_override row only after
--   set_config('app.product_description.human', 'on', true)
-- inside the same transaction (the item-master PATCH does this). Bulk/refresh
-- connections never set it, so the trigger fires for them.
--
-- Idempotent: every object IF NOT EXISTS / OR REPLACE; re-apply is a no-op.
-- Rollback: drop trigger item_product_description_write_guard on
-- <s>.item_product_description and trigger product_description_audit on both
-- tables, drop function <s>.item_product_description_protect_human_override,
-- drop function <s>.product_description_row_audit, drop tables
-- <s>.item_product_description_history, <s>.item_product_description,
-- <s>.mg_combination_description_history, <s>.mg_combination_description.

set lock_timeout = '5s';
set statement_timeout = '2min';

do $do$
declare
  has_dflow      boolean := to_regnamespace('dflow') is not null;
  has_dflow_prod boolean := to_regnamespace('dflow_prod') is not null;
  target         text;
begin
  if has_dflow_prod then
    target := 'dflow_prod';
  elsif has_dflow then
    target := 'dflow';
  else
    target := null;
  end if;

  if target is not null then
    if to_regclass('core."merchGroup"') is null then
      raise exception '#5020/20261029043759 self-check: core."merchGroup" is missing on this database — cannot create the combination FKs'
        using errcode = 'feature_not_supported';
    end if;
    if to_regclass(format('%I."itemHeader"', target)) is null then
      raise exception '#5020/20261029043759 self-check: schema % has no "itemHeader" — wrong database for this arm', target
        using errcode = 'feature_not_supported';
    end if;

    -- Combination table: one row per MG01+MG02+MG03 with its verified state and provenance.
    execute format($sql$
      create table if not exists %I.mg_combination_description (
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
      )$sql$, target);

    execute format($sql$
      create table if not exists %I.mg_combination_description_history (
        history_id bigint generated always as identity primary key,
        history_at timestamptz not null default now(),
        like %I.mg_combination_description including defaults
      )$sql$, target, target);

    -- Per-item copy: description, provenance and the never-machine-overwritten flag.
    execute format($sql$
      create table if not exists %I.item_product_description (
        item_fk integer primary key
          references %I."itemHeader"(item_id_pk) on delete cascade,
        combination_fk bigint references %I.mg_combination_description(id),
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
      )$sql$, target, target, target);

    execute format($sql$
      create table if not exists %I.item_product_description_history (
        history_id bigint generated always as identity primary key,
        history_at timestamptz not null default now(),
        like %I.item_product_description including defaults
      )$sql$, target, target);

    -- Audit: every UPDATE/DELETE copies the OLD row into the matching history table.
    -- (Inner format placeholders are doubled: the outer format() owns single ones.)
    execute format($sql$
      create or replace function %I.product_description_row_audit() returns trigger as $fn$
      declare
        cols text;
      begin
        select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
          into cols
        from information_schema.columns
        where table_schema = tg_table_schema
          and table_name = tg_table_name;
        execute format('insert into %%I.%%I (%%s) select $1.*',
          tg_table_schema, tg_table_name || '_history', cols)
          using old;
        return null;
      end
      $fn$ language plpgsql$sql$, target);

    execute format($sql$
      drop trigger if exists product_description_audit on %I.mg_combination_description$sql$, target);
    execute format($sql$
      create trigger product_description_audit
        after update or delete on %I.mg_combination_description
        for each row execute function %I.product_description_row_audit()$sql$, target, target);

    execute format($sql$
      drop trigger if exists product_description_audit on %I.item_product_description$sql$, target);
    execute format($sql$
      create trigger product_description_audit
        after update or delete on %I.item_product_description
        for each row execute function %I.product_description_row_audit()$sql$, target, target);

    -- Guard: a human override is never created, changed or cleared by a machine
    -- connection — only by a session that set app.product_description.human.
    execute format($sql$
      create or replace function %I.item_product_description_protect_human_override() returns trigger as $fn$
      begin
        if coalesce(current_setting('app.product_description.human', true), '') = ''
          and (
            (old.is_human_override
              and (new.description is distinct from old.description
                   or new.is_human_override is distinct from old.is_human_override))
            or (not old.is_human_override and new.is_human_override)
          )
        then
          raise exception 'item_product_description %% carries or claims a human override; only a human session may set, change or clear it (set app.product_description.human in the transaction)',
            old.item_fk using errcode = 'check_violation';
        end if;
        return new;
      end
      $fn$ language plpgsql$sql$, target);

    execute format($sql$
      drop trigger if exists item_product_description_write_guard on %I.item_product_description$sql$, target);
    execute format($sql$
      create trigger item_product_description_write_guard
        before update on %I.item_product_description
        for each row execute function %I.item_product_description_protect_human_override()$sql$, target, target);

    -- Review list and run-scoped rollback support.
    execute format($sql$
      create index if not exists item_product_description_combination_idx
        on %I.item_product_description (combination_fk)$sql$, target);

    execute format($sql$
      create index if not exists item_product_description_review_idx
        on %I.item_product_description (item_fk) where description is null$sql$, target);

    execute format($sql$
      create index if not exists item_product_description_run_idx
        on %I.item_product_description (run_id)$sql$, target);

    execute format($sql$
      create index if not exists mg_combination_description_run_idx
        on %I.mg_combination_description (run_id)$sql$, target);

    if target = 'dflow_prod' then
      execute format($sql$
        grant select, insert, update, delete
        on %I.mg_combination_description,
          %I.mg_combination_description_history,
          %I.item_product_description,
          %I.item_product_description_history
        to designflow_prod_item_master_grants$sql$, target, target, target, target);
    end if;
  end if;
end
$do$;
