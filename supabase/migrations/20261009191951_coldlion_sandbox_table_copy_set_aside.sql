-- Issue #3869 (claim #4147): set aside the DesignFlow sandbox's 2026-09-29 ColdLion
-- table copy so the canonical ColdLion landing migrations can be applied there.
--
-- The DesignFlow sandbox (xupnyeifmpsacrqahwwm) received a plain TABLE COPY of the
-- coldlion schema on 2026-09-29: different keys (no surrogate `id`, `item_no` instead of
-- `master_item_no`, no `sales_order_line_no`), no page ledger, no functions, and none of
-- the landing migrations in its ledger. The landing loader cannot write to it, and no
-- additive change can make it compatible. This migration MOVES every table of that copy,
-- unchanged and with all rows, into schema coldlion_sandbox_copy_20260929. Nothing is
-- dropped or edited; the copy stays readable for comparison and can be moved back.
--
-- Everywhere else this is a NO-OP. It acts only when coldlion.order_history_line exists
-- WITHOUT the canonical `id` column and coldlion.window_ledger exists WITHOUT the canonical
-- `stage_code` column -- the copy's shape. Shared production and shared preview carry the
-- canonical landing tables (id and stage_code present), so they pass through untouched,
-- as does any database built from the migrations in order.

do $set_aside$
declare
  v_copy_shape boolean;
  v_expected text[] := array[
    'change_log', 'customer', 'item_detail', 'item_header', 'item_merch_group',
    'merch_group_detail', 'merch_group_header', 'order_history_component',
    'order_history_line', 'prod_history_component', 'prod_history_last_lookup',
    'prod_history_line', 'salesperson', 'season', 'sync_run', 'vendor', 'window_ledger'
  ];
  v_actual text[];
  v_other text;
  v_table text;
begin
  v_copy_shape :=
        to_regclass('coldlion.order_history_line') is not null
    and to_regclass('coldlion.window_ledger') is not null
    and not exists (
          select 1 from pg_attribute
           where attrelid = 'coldlion.order_history_line'::regclass
             and attname = 'id' and attnum > 0 and not attisdropped)
    and not exists (
          select 1 from pg_attribute
           where attrelid = 'coldlion.window_ledger'::regclass
             and attname = 'stage_code' and attnum > 0 and not attisdropped);

  if not v_copy_shape then
    raise notice '#3869/20261009191951: coldlion is not the 2026-09-29 sandbox table copy; nothing to set aside';
    return;
  end if;

  if to_regnamespace('coldlion_sandbox_copy_20260929') is not null then
    raise exception '#3869/20261009191951: schema coldlion_sandbox_copy_20260929 already exists; refusing to merge into it';
  end if;

  -- The copy must be exactly the 17 known tables and nothing else: no views, functions,
  -- sequences or types that a move would orphan or that a later migration would need.
  select array_agg(c.relname::text order by c.relname) into v_actual
    from pg_class c
   where c.relnamespace = 'coldlion'::regnamespace and c.relkind in ('r', 'p');
  if v_actual is distinct from (select array_agg(x order by x) from unnest(v_expected) x) then
    raise exception '#3869/20261009191951: coldlion tables differ from the known 2026-09-29 copy: %', v_actual;
  end if;

  select string_agg(format('%s %s', c.relkind, c.relname), ', ') into v_other
    from pg_class c
   where c.relnamespace = 'coldlion'::regnamespace
     and c.relkind not in ('r', 'p', 'i', 'S', 't');
  if v_other is not null then
    raise exception '#3869/20261009191951: coldlion holds non-table relations: %', v_other;
  end if;
  if exists (select 1 from pg_proc where pronamespace = 'coldlion'::regnamespace)
     or exists (select 1 from pg_type t where t.typnamespace = 'coldlion'::regnamespace
                  and t.typtype in ('e', 'd', 'c')
                  and not exists (select 1 from pg_class c where c.reltype = t.oid)) then
    raise exception '#3869/20261009191951: coldlion holds functions or free-standing types; not the known copy';
  end if;

  create schema coldlion_sandbox_copy_20260929;
  comment on schema coldlion_sandbox_copy_20260929 is
    'DesignFlow sandbox only: the 2026-09-29 table copy of coldlion, moved aside unchanged by migration 20261009191951 (issue #3869) so the canonical landing tables could be created. Read-only archive; not written by any loader.';
  revoke all on schema coldlion_sandbox_copy_20260929 from public;

  foreach v_table in array v_expected loop
    execute format('alter table coldlion.%I set schema coldlion_sandbox_copy_20260929', v_table);
  end loop;

  if exists (select 1 from pg_class where relnamespace = 'coldlion'::regnamespace and relkind in ('r', 'p', 'v', 'm')) then
    raise exception '#3869/20261009191951 post-check: relations remain in coldlion after the move';
  end if;
  raise notice '#3869/20261009191951: moved % coldlion copy tables to coldlion_sandbox_copy_20260929', array_length(v_expected, 1);
end
$set_aside$;
