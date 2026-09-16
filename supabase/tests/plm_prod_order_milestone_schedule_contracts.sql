-- #3091 contracts: plm.prod_order_milestone_schedule.
-- Synthetic rows only; the CI runner wraps this file in begin/rollback.

do $$
declare
  header_id integer;
  factory_id integer;
begin
  if to_regclass('plm.prod_order_milestone_schedule') is null then
    raise exception 'plm.prod_order_milestone_schedule is missing';
  end if;

  if not exists (select 1 from pg_index
                  where indexrelid = 'plm.prod_order_header_id_key'::regclass
                    and indisunique and indrelid = 'plm."ProdOrderHeader"'::regclass) then
    raise exception 'plm."ProdOrderHeader"(id) must be uniquely indexed';
  end if;

  if not exists (select 1 from pg_index
                  where indexrelid = 'plm.prod_order_milestone_schedule_upsert_key'::regclass and indisunique) then
    raise exception 'upsert key must be unique';
  end if;

  if to_regclass('plm.prod_order_milestone_schedule_status_needed_idx') is null then
    raise exception 'overdue scan index is missing';
  end if;

  if (select count(*) from pg_constraint
       where conrelid = 'plm.prod_order_milestone_schedule'::regclass and contype = 'f'
         and confrelid in ('plm."ProdOrderHeader"'::regclass, 'plm."FactoryTime"'::regclass)) <> 2 then
    raise exception 'expected foreign keys to ProdOrderHeader and FactoryTime';
  end if;

  if not (select relrowsecurity from pg_class where oid = 'plm.prod_order_milestone_schedule'::regclass) then
    raise exception 'row level security must be enabled';
  end if;

  if has_table_privilege('anon', 'plm.prod_order_milestone_schedule', 'select')
     or has_table_privilege('authenticated', 'plm.prod_order_milestone_schedule', 'select') then
    raise exception 'browser roles must have no access';
  end if;

  -- Behaviour, when a production order exists to attach to.
  select id into header_id from plm."ProdOrderHeader" limit 1;
  if header_id is not null then
    insert into plm.prod_order_milestone_schedule(prod_order_header_id, stage_name, status, needed_date)
    values (header_id, 'zztest Mass Production Start', 'Pending', current_date)
    on conflict (prod_order_header_id, stage_name, sku)
    do update set status = excluded.status, computed_at = now();
    insert into plm.prod_order_milestone_schedule(prod_order_header_id, stage_name, status, needed_date)
    values (header_id, 'zztest Mass Production Start', 'Overdue', current_date)
    on conflict (prod_order_header_id, stage_name, sku)
    do update set status = excluded.status, computed_at = now();
    if (select count(*) from plm.prod_order_milestone_schedule
         where prod_order_header_id = header_id and stage_name = 'zztest Mass Production Start') <> 1 then
      raise exception 'upsert was not idempotent';
    end if;

    begin
      insert into plm.prod_order_milestone_schedule(prod_order_header_id, stage_name, status)
      values (header_id, '  ', 'Pending');
      raise exception 'blank stage name was accepted';
    exception when check_violation then null;
    end;
  end if;
end $$;
