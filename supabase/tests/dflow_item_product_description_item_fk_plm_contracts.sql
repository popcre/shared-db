-- Invented fixtures only. Run from the repository root on a disposable sandbox
-- database as owner with psql -X -v ON_ERROR_STOP=1 -f this-file.
-- Keep the migration's real statements inside this test transaction, removing
-- only its outer transaction commands and full-line comments. This permits
-- catching its actual refusal and rolling back every fixture and DDL change.
\set ON_ERROR_STOP on
begin;
-- CI carries both families. Remove production only inside the rolled-back test.
drop schema if exists dflow_prod cascade;
create schema if not exists core;
create schema if not exists dflow;
create schema if not exists plm;
create table if not exists core."merchGroup" (mg_id integer primary key);
create table if not exists dflow."itemHeader" (item_id_pk integer primary key);
create table if not exists plm."itemHeader" (item_id_pk integer primary key);
\i supabase/migrations/20261106050346_dflow_product_description.sql
\set migration_body `sed '/^--/d; /^begin;$/d; /^commit;$/d' supabase/migrations/20261112205825_dflow_item_product_description_item_fk_plm.sql`
select set_config('zz.item_fk.migration', :'migration_body', true);

-- Reproduce the original key, including on stacks that already applied the fix.
alter table dflow.item_product_description
  drop constraint item_product_description_item_fk_fkey;
alter table dflow.item_product_description
  add constraint item_product_description_item_fk_fkey
  foreign key (item_fk) references dflow."itemHeader"(item_id_pk) on delete cascade;

do $$
declare
  base integer;
begin
  select greatest(coalesce((select max(item_id_pk) from dflow."itemHeader"), 0),
                  coalesce((select max(item_id_pk) from plm."itemHeader"), 0)) + 1000 into base;
  perform set_config('zz.item_fk.base', base::text, true);
  insert into dflow."itemHeader" (item_id_pk) overriding system value
    values (base), (base+1), (base+2);
  insert into plm."itemHeader" (item_id_pk) overriding system value
    values (base), (base+3), (base+4);
  insert into dflow.item_product_description (item_fk, description, run_id)
    values (base, 'ZZ retained', 'zz-item-fk'), (base+1, 'ZZ archived', 'zz-item-fk');
  perform set_config('app.product_description.human', 'on', true);
  insert into dflow.item_product_description (item_fk, description, source, is_human_override, run_id)
    values (base+2, 'ZZ human', 'human', true, 'zz-item-fk');
  perform set_config('app.product_description.human', 'off', true);

  begin
    execute current_setting('zz.item_fk.migration');
    raise exception 'Migration accepted an orphaned human override';
  exception when check_violation then
    if sqlerrm not like '%a human override belongs to an item absent%' then
      raise;
    end if;
  end;
  if (select count(*) from dflow.item_product_description where run_id = 'zz-item-fk') <> 3
     or exists (select 1 from dflow.item_product_description_history where run_id = 'zz-item-fk')
     or not exists (select 1 from pg_constraint
       where conrelid = 'dflow.item_product_description'::regclass
         and conname = 'item_product_description_item_fk_fkey'
         and confrelid = 'dflow."itemHeader"'::regclass) then
    raise exception 'Refused migration changed rows, history or the old key';
  end if;
  -- Give the override a valid new parent, preserving its contents and guard.
  insert into plm."itemHeader" (item_id_pk) overriding system value values (base+2);
  execute current_setting('zz.item_fk.migration');
  if exists (select 1 from dflow.item_product_description where item_fk = base+1)
     or (select count(*) from dflow.item_product_description_history
         where item_fk = base+1 and description = 'ZZ archived' and run_id = 'zz-item-fk') <> 1
     or (select count(*) from dflow.item_product_description
         where (item_fk = base and description = 'ZZ retained')
            or (item_fk = base+2 and description = 'ZZ human' and is_human_override)) <> 2 then
    raise exception 'Cleanup failed to preserve valid rows or audit the orphan';
  end if;

  insert into dflow.item_product_description (item_fk, description, run_id)
    values (base+3, 'ZZ new parent only', 'zz-item-fk');
  begin
    insert into dflow.item_product_description (item_fk) values (base+1);
    raise exception 'Old-parent-only item was accepted';
  exception when foreign_key_violation then null;
  end;
  -- Cascade still audits machine rows and refuses deletion of human overrides.
  delete from plm."itemHeader" where item_id_pk = base+3;
  if exists (select 1 from dflow.item_product_description where item_fk = base+3)
     or (select count(*) from dflow.item_product_description_history where item_fk = base+3) <> 1 then
    raise exception 'Parent cascade failed to delete and audit the machine row';
  end if;
  begin
    delete from plm."itemHeader" where item_id_pk = base+2;
    raise exception 'Parent cascade bypassed the human override guard';
  exception when check_violation then null;
  end;
  if not exists (select 1 from plm."itemHeader" where item_id_pk = base+2) then
    raise exception 'Refused parent deletion lost the parent';
  end if;
  execute current_setting('zz.item_fk.migration');
  if (select count(*) from dflow.item_product_description where run_id = 'zz-item-fk') <> 2
     or (select count(*) from dflow.item_product_description_history where run_id = 'zz-item-fk') <> 2 then
    raise exception 'Reapply changed fixture rows or history';
  end if;
end $$;

-- A same-name key on the right table with the wrong delete action and
-- unvalidated state must be repaired, rather than incorrectly skipped.
alter table dflow.item_product_description
  drop constraint item_product_description_item_fk_fkey;
alter table dflow.item_product_description
  add constraint item_product_description_item_fk_fkey foreign key (item_fk)
  references plm."itemHeader"(item_id_pk) not valid;
do $$ begin execute current_setting('zz.item_fk.migration'); end $$;

-- Exact catalog shape after apply, reapply and repair.
do $$
begin
  if not exists (
    select 1 from pg_constraint c
    where c.conrelid = 'dflow.item_product_description'::regclass
      and c.conname = 'item_product_description_item_fk_fkey'
      and c.contype = 'f' and c.convalidated and c.confdeltype = 'c'
      and c.confrelid = 'plm."itemHeader"'::regclass
      and c.conkey = array[(select attnum from pg_attribute
        where attrelid = c.conrelid and attname = 'item_fk')]
      and c.confkey = array[(select attnum from pg_attribute
        where attrelid = c.confrelid and attname = 'item_id_pk')]
  ) or exists (select 1 from pg_constraint
    where conrelid = 'dflow.item_product_description'::regclass
      and conname = 'item_product_description_item_fk_plm_fkey') then
    raise exception 'Repointed key has the wrong catalog shape';
  end if;
end $$;
rollback;
