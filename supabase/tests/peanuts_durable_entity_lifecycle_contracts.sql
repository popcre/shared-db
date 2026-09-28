-- #3684: synthetic, rollback-only Peanuts durable entity state contracts.
-- No licensed value is used; every identity below is invented.

begin;

do $catalog$
declare v_table text;
begin
  foreach v_table in array array['peanuts_entity_lifecycle','peanuts_lifecycle_publication'] loop
    if not (select relrowsecurity from pg_class where oid = format('plm.%I', v_table)::regclass) then
      raise exception 'RLS is disabled for plm.%', v_table;
    end if;
    if has_table_privilege('anon', format('plm.%I', v_table), 'select')
       or not has_table_privilege('authenticated', format('plm.%I', v_table), 'select')
       or has_table_privilege('authenticated', format('plm.%I', v_table), 'insert')
       or has_table_privilege('service_role', format('plm.%I', v_table), 'insert')
       or has_table_privilege('service_role', format('plm.%I', v_table), 'update')
       or has_table_privilege('service_role', format('plm.%I', v_table), 'delete') then
      raise exception 'Peanuts lifecycle grants are incorrect for plm.%', v_table;
    end if;
  end loop;
  if has_function_privilege('anon', 'plm.peanuts_publish_lifecycle(uuid)', 'execute')
     or has_function_privilege('authenticated', 'plm.peanuts_publish_lifecycle(uuid)', 'execute')
     or not has_function_privilege('service_role', 'plm.peanuts_publish_lifecycle(uuid)', 'execute') then
    raise exception 'Peanuts publish function execute grants are incorrect';
  end if;
end
$catalog$;

-- A..D complete zero-failure captures; C uses another customer account; U complete but
-- with one unreachable asset (partial coverage); R rejected (authentication loss);
-- O older than A.
insert into plm.peanuts_capture (id, capture_key, source_repository, source_commit_sha,
  source_manifest_sha256, portal_base_url, api_endpoint, source_customer_id, source_captured_at,
  status, load_completed_at, expected_counts, portal_reported_asset_total, assets_captured,
  assets_unreachable, deep_paging_partitioned, vocabularies_loaded_from_source,
  error_summary, raw_summary, created_by)
select v.id::uuid, 'contract:' || v.id, 'synthetic/repo', repeat('a', 40), repeat('b', 64),
       'https://example.invalid', 'https://example.invalid/api', v.customer, v.at::timestamptz,
       v.status, case when v.status = 'complete' then now() end, '{}'::jsonb,
       v.total, v.captured, v.total - v.captured, true, true,
       case when v.status = 'complete' then '[]' else '[{"code":"synthetic"}]' end::jsonb,
       '{}'::jsonb, 'contract'
  from (values
    ('36840000-0000-4000-8000-00000000000a', '2026-09-01T00:00:00Z', 'complete', 'cust-1', 2, 2),
    ('36840000-0000-4000-8000-00000000000b', '2026-09-02T00:00:00Z', 'complete', 'cust-1', 1, 1),
    ('36840000-0000-4000-8000-00000000000c', '2026-09-03T00:00:00Z', 'complete', 'cust-2', 3, 3),
    ('36840000-0000-4000-8000-00000000000d', '2026-09-04T00:00:00Z', 'complete', 'cust-2', 1, 1),
    ('36840000-0000-4000-8000-0000000000ee', '2026-09-05T00:00:00Z', 'complete', 'cust-2', 2, 1),
    ('36840000-0000-4000-8000-0000000000ff', '2026-09-06T00:00:00Z', 'rejected', 'cust-2', 1, 0),
    ('36840000-0000-4000-8000-000000000001', '2026-08-01T00:00:00Z', 'complete', 'cust-1', 0, 0),
    ('36840000-0000-4000-8000-000000000006', '2026-09-07T00:00:00Z', 'complete', 'cust-2', 3, 3)
  ) v(id, at, status, customer, total, captured);

insert into plm.peanuts_asset (capture_id, source_object_id, file_name, checksum, raw)
select v.cap::uuid, v.obj, 'f', v.sum, '{}'::jsonb
  from (values
    ('36840000-0000-4000-8000-00000000000a', 'obj-1', 's1'),
    ('36840000-0000-4000-8000-00000000000a', 'obj-2', 's1'),
    ('36840000-0000-4000-8000-00000000000b', 'obj-1', 's2'),
    ('36840000-0000-4000-8000-00000000000c', 'obj-2', 's1'),
    ('36840000-0000-4000-8000-00000000000c', 'obj-3', 's1'),
    ('36840000-0000-4000-8000-00000000000c', 'obj-4', 's1'),
    ('36840000-0000-4000-8000-00000000000d', 'obj-5', 's1'),
    ('36840000-0000-4000-8000-0000000000ee', 'obj-5', 's1'),
    ('36840000-0000-4000-8000-000000000006', 'obj-5', 's1'),
    ('36840000-0000-4000-8000-000000000006', 'obj-3', 's1'),
    ('36840000-0000-4000-8000-000000000006', 'obj-4', 's1')
  ) v(cap, obj, sum);

insert into plm.peanuts_art_program (capture_id, value_key, value_label, source_field_name,
  source_field_label, is_multi_select, asset_count, raw)
values ('36840000-0000-4000-8000-00000000000a', 'program-a', 'Program A', 'f', 'F', true, 0, '{}'::jsonb);
insert into plm.peanuts_initiative (capture_id, value_key, value_label, source_field_name,
  source_field_label, is_multi_select, asset_count, raw)
values ('36840000-0000-4000-8000-00000000000a', 'initiative-a', 'Initiative A', 'f', 'F', false, 0, '{}'::jsonb);

set local role service_role;
do $refusals$
declare v_id text;
begin
  foreach v_id in array array['36840000-0000-4000-8000-0000000000ff','36840000-0000-4000-8000-0000000000ee'] loop
    begin
      perform plm.peanuts_publish_lifecycle(v_id::uuid);
      raise exception 'publish accepted an unqualified capture %', v_id;
    exception when sqlstate '22023' then null;
    end;
  end loop;
  begin
    perform plm.peanuts_publish_lifecycle('36840000-0000-4000-8000-00000000abcd');
    raise exception 'publish accepted an unknown capture';
  exception when sqlstate 'P0002' then null;
  end;
end
$refusals$;

select plm.peanuts_publish_lifecycle('36840000-0000-4000-8000-00000000000a');
reset role;

do $bootstrap$
begin
  if (select mode from plm.peanuts_lifecycle_publication where capture_id = '36840000-0000-4000-8000-00000000000a') <> 'bootstrap' then
    raise exception 'first publication is not a bootstrap';
  end if;
  if (select count(*) from plm.peanuts_entity_lifecycle) <> 4 then
    raise exception 'bootstrap did not record two assets, one art program and one initiative';
  end if;
  if not exists (select 1 from pg_locks where locktype = 'advisory' and pid = pg_backend_pid() and granted
                 and objsubid = 1
                 and ((classid::bigint << 32) | objid::bigint) = hashtextextended('plm.peanuts_publish_lifecycle', 0)) then
    raise exception 'publication did not hold its transaction advisory lock';
  end if;
end
$bootstrap$;

set local role service_role;
do $order$
begin
  begin
    perform plm.peanuts_publish_lifecycle('36840000-0000-4000-8000-00000000000a');
    raise exception 'publish accepted a capture twice';
  exception when unique_violation then null;
  end;
  begin
    perform plm.peanuts_publish_lifecycle('36840000-0000-4000-8000-000000000001');
    raise exception 'publish accepted an older capture';
  exception when sqlstate '22023' then null;
  end;
end
$order$;

-- B: comparable. obj-2 and the art program are withdrawn; the initiative is retired.
select plm.peanuts_publish_lifecycle('36840000-0000-4000-8000-00000000000b');
reset role;

do $comparable$
begin
  if (select mode from plm.peanuts_lifecycle_publication where capture_id = '36840000-0000-4000-8000-00000000000b') <> 'comparable' then
    raise exception 'same account did not compare';
  end if;
  if not exists (select 1 from plm.peanuts_entity_lifecycle where entity_kind = 'asset' and entity_key = 'obj-2'
                 and status = 'withdrawn' and first_withdrawn_at = '2026-09-02T00:00:00Z') then
    raise exception 'absent baseline asset was not withdrawn';
  end if;
  if not exists (select 1 from plm.peanuts_entity_lifecycle where entity_kind = 'art_program' and status = 'withdrawn') then
    raise exception 'absent art program was not withdrawn';
  end if;
  if not exists (select 1 from plm.peanuts_entity_lifecycle where entity_kind = 'initiative'
                 and status = 'retired' and retired_at is not null and withdrawn_at is null) then
    raise exception 'absent initiative was not retired (owner ruling 6.20)';
  end if;
  if not exists (select 1 from plm.peanuts_entity_lifecycle where entity_key = 'obj-1'
                 and last_changed_capture_id = '36840000-0000-4000-8000-00000000000b'
                 and first_seen_capture_id = '36840000-0000-4000-8000-00000000000a') then
    raise exception 'changed asset lost first sighting or change marker';
  end if;
end
$comparable$;

-- C: another customer account; obj-2 reappears, obj-1 is not withdrawn.
set local role service_role;
select plm.peanuts_publish_lifecycle('36840000-0000-4000-8000-00000000000c');
reset role;

do $rebaseline$
begin
  if (select mode from plm.peanuts_lifecycle_publication where capture_id = '36840000-0000-4000-8000-00000000000c') <> 'rebaseline' then
    raise exception 'different account was compared';
  end if;
  if not exists (select 1 from plm.peanuts_entity_lifecycle where entity_key = 'obj-1' and status = 'active') then
    raise exception 'incomparable run withdrew an entity';
  end if;
  if not exists (select 1 from plm.peanuts_entity_lifecycle where entity_key = 'obj-2'
                 and status = 'active' and first_withdrawn_at = '2026-09-02T00:00:00Z') then
    raise exception 'reappearing asset was not reactivated with history kept';
  end if;
end
$rebaseline$;

-- D: comparable with C but drops three of three baseline assets: held.
set local role service_role;
select plm.peanuts_publish_lifecycle('36840000-0000-4000-8000-00000000000d');
reset role;

do $held$
begin
  if (select mode from plm.peanuts_lifecycle_publication where capture_id = '36840000-0000-4000-8000-00000000000d') <> 'withdrawal_held' then
    raise exception 'bulk drop was not held';
  end if;
  if exists (select 1 from plm.peanuts_entity_lifecycle where withdrawn_capture_id = '36840000-0000-4000-8000-00000000000d') then
    raise exception 'held publication withdrew an entity';
  end if;
end
$held$;

-- After a held publication, the next comparable run re-evaluates the held drop instead
-- of orphaning it: obj-2 was last seen before the hold and is now withdrawn.
set local role service_role;
select plm.peanuts_publish_lifecycle('36840000-0000-4000-8000-000000000006');
reset role;

do $after_hold$
begin
  if (select mode from plm.peanuts_lifecycle_publication where capture_id = '36840000-0000-4000-8000-000000000006') <> 'comparable' then
    raise exception 'run after a held publication did not compare';
  end if;
  if not exists (select 1 from plm.peanuts_entity_lifecycle where entity_key = 'obj-2'
                 and status = 'withdrawn' and withdrawn_capture_id = '36840000-0000-4000-8000-000000000006') then
    raise exception 'drop held earlier was orphaned instead of re-evaluated';
  end if;
  if not exists (select 1 from plm.peanuts_entity_lifecycle where entity_key = 'obj-5' and status = 'active') then
    raise exception 'entity seen after the hold is not active';
  end if;
end
$after_hold$;

-- Exact objects: column order and named constraints, not just names that resolve.
do $exact$
begin
  if (select string_agg(attname, ',' order by attnum) from pg_attribute
       where attrelid = 'plm.peanuts_entity_lifecycle'::regclass and attnum > 0 and not attisdropped)
     <> 'entity_kind,entity_key,first_seen_capture_id,first_seen_at,last_seen_capture_id,last_seen_at,last_changed_capture_id,change_signal,status,withdrawn_at,first_withdrawn_at,withdrawn_capture_id,retired_at' then
    raise exception 'plm.peanuts_entity_lifecycle columns differ from the reviewed shape';
  end if;
  if (select string_agg(attname, ',' order by attnum) from pg_attribute
       where attrelid = 'plm.peanuts_lifecycle_publication'::regclass and attnum > 0 and not attisdropped)
     <> 'capture_id,baseline_capture_id,mode,derivation_contract,scope_sha256,source_captured_at,counts,published_at' then
    raise exception 'plm.peanuts_lifecycle_publication columns differ from the reviewed shape';
  end if;
  if (select count(*) from pg_constraint where conrelid = 'plm.peanuts_entity_lifecycle'::regclass
       and conname in ('peanuts_entity_lifecycle_pkey','peanuts_entity_lifecycle_kind_chk','peanuts_entity_lifecycle_status_chk',
                       'peanuts_entity_lifecycle_withdrawn_at_chk','peanuts_entity_lifecycle_history_chk')) <> 5
     or (select count(*) from pg_constraint where conrelid = 'plm.peanuts_entity_lifecycle'::regclass
          and contype = 'f' and confrelid = 'plm.peanuts_lifecycle_publication'::regclass) <> 4
     or (select count(*) from pg_constraint where conrelid = 'plm.peanuts_lifecycle_publication'::regclass
          and conname in ('peanuts_lifecycle_publication_pkey','peanuts_lifecycle_publication_mode_chk',
                          'peanuts_lifecycle_publication_baseline_chk','peanuts_lifecycle_publication_scope_chk')) <> 4 then
    raise exception 'durable-state constraints differ from the reviewed shape';
  end if;
  if not (select prosecdef from pg_proc where oid = 'plm.peanuts_publish_lifecycle(uuid)'::regprocedure) then
    raise exception 'publish function is not SECURITY DEFINER';
  end if;
end
$exact$;

set local role service_role;
do $direct$
begin
  begin
    delete from plm.peanuts_entity_lifecycle;
    raise exception 'service_role deleted lifecycle rows';
  exception when insufficient_privilege then null;
  end;
end
$direct$;
reset role;

do $constraint$
begin
  begin
    update plm.peanuts_entity_lifecycle set status = 'withdrawn', withdrawn_at = now(),
      first_withdrawn_at = now(), withdrawn_capture_id = '36840000-0000-4000-8000-00000000000d'
     where entity_kind = 'initiative';
    raise exception 'an initiative was allowed to be withdrawn';
  exception when check_violation then null;
  end;
end
$constraint$;

rollback;
