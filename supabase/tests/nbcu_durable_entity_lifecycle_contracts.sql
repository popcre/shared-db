-- #3683: synthetic, rollback-only NBCU durable entity state contracts.
-- No licensed value is used; every identity below is invented.

begin;

do $catalog$
declare v_table text;
begin
  foreach v_table in array array['nbcu_entity_lifecycle','nbcu_lifecycle_publication'] loop
    if not (select relrowsecurity from pg_class where oid = format('plm.%I', v_table)::regclass) then
      raise exception 'RLS is disabled for plm.%', v_table;
    end if;
    if has_table_privilege('anon', format('plm.%I', v_table), 'select')
       or not has_table_privilege('authenticated', format('plm.%I', v_table), 'select')
       or has_table_privilege('authenticated', format('plm.%I', v_table), 'insert')
       or has_table_privilege('service_role', format('plm.%I', v_table), 'insert')
       or has_table_privilege('service_role', format('plm.%I', v_table), 'update')
       or has_table_privilege('service_role', format('plm.%I', v_table), 'delete') then
      raise exception 'NBCU lifecycle grants are incorrect for plm.%', v_table;
    end if;
  end loop;
  if has_function_privilege('anon', 'plm.nbcu_publish_lifecycle(uuid)', 'execute')
     or has_function_privilege('authenticated', 'plm.nbcu_publish_lifecycle(uuid)', 'execute')
     or not has_function_privilege('service_role', 'plm.nbcu_publish_lifecycle(uuid)', 'execute') then
    raise exception 'NBCU publish function execute grants are incorrect';
  end if;
end
$catalog$;

-- Synthetic captures. A..D are complete; R is rejected (authentication loss shows up
-- as a rejected finalize); E is complete but carries an error summary.
insert into plm.nbcu_capture (id, capture_key, source_repository, source_commit_sha,
  source_manifest_sha256, portal_base_url, source_captured_at, status, load_completed_at,
  expected_counts, observed_counts, error_summary, raw_summary, created_by)
select v.id::uuid, 'contract:' || v.id, 'synthetic/repo', repeat('a', 40), repeat('b', 64),
       'https://example.invalid', v.at::timestamptz, v.status,
       case when v.status = 'complete' then now() end,
       '{}'::jsonb, '{}'::jsonb, v.err::jsonb, '{}'::jsonb, 'contract'
  from (values
    ('36830000-0000-4000-8000-00000000000a', '2026-09-01T00:00:00Z', 'complete', '[]'),
    ('36830000-0000-4000-8000-00000000000b', '2026-09-02T00:00:00Z', 'complete', '[]'),
    ('36830000-0000-4000-8000-00000000000c', '2026-09-03T00:00:00Z', 'complete', '[]'),
    ('36830000-0000-4000-8000-00000000000d', '2026-09-04T00:00:00Z', 'complete', '[]'),
    ('36830000-0000-4000-8000-00000000000e', '2026-09-05T00:00:00Z', 'complete', '[{"code":"synthetic"}]'),
    ('36830000-0000-4000-8000-0000000000ff', '2026-09-06T00:00:00Z', 'rejected', '[{"code":"synthetic"}]'),
    ('36830000-0000-4000-8000-000000000001', '2026-08-01T00:00:00Z', 'complete', '[]'),
    ('36830000-0000-4000-8000-000000000006', '2026-09-07T00:00:00Z', 'complete', '[]')
  ) v(id, at, status, err);

insert into plm.nbcu_scope (capture_id, scope_key, scope_label, scope_href, page_count,
  indexed_rows, unique_assets, terminal, missing_offsets, source_files, raw)
select v.cap::uuid, 'href-sha256:' || repeat(v.k, 64), 'scope ' || v.k, 'https://example.invalid/' || v.k,
       1, 1, 1, true, '{}', '[]'::jsonb, '{}'::jsonb
  from (values
    ('36830000-0000-4000-8000-00000000000a','1'), ('36830000-0000-4000-8000-00000000000a','2'),
    ('36830000-0000-4000-8000-00000000000b','1'), ('36830000-0000-4000-8000-00000000000b','2'),
    ('36830000-0000-4000-8000-00000000000c','1'),
    ('36830000-0000-4000-8000-00000000000d','1'),
    ('36830000-0000-4000-8000-00000000000e','1'),
    ('36830000-0000-4000-8000-0000000000ff','1'),
    ('36830000-0000-4000-8000-000000000001','1'),
    ('36830000-0000-4000-8000-000000000006','1')
  ) v(cap, k);

insert into plm.nbcu_asset (capture_id, asset_source_key, asset_path, file_name, display_size,
  display_modified, studio_labels, ip_family_labels, property_labels, character_labels,
  restriction_labels, style_guide_natural_keys, scope_paths, source_captured_at, source_url, raw, source_hash)
select v.cap::uuid, v.path, v.path, 'f', '1 KB', v.modified, '[]', '[]', '[]', '[]', '[]', '[]', '[]',
       now(), 'https://example.invalid', '{}'::jsonb, repeat('c', 64)
  from (values
    ('36830000-0000-4000-8000-00000000000a', '/content/asset-share-commons/en/details/image.html/content/dam/synthetic/one.png', 'm1'),
    ('36830000-0000-4000-8000-00000000000a', '/content/dam/synthetic/two.png', 'm1'),
    ('36830000-0000-4000-8000-00000000000b', '/content/dam/synthetic/one.png', 'm2'),
    ('36830000-0000-4000-8000-00000000000c', '/content/dam/synthetic/two.png', 'm1'),
    ('36830000-0000-4000-8000-00000000000c', '/content/dam/synthetic/three.png', 'm1'),
    ('36830000-0000-4000-8000-00000000000c', '/content/dam/synthetic/four.png', 'm1'),
    ('36830000-0000-4000-8000-00000000000d', '/content/dam/synthetic/five.png', 'm1'),
    ('36830000-0000-4000-8000-00000000000e', '/content/dam/synthetic/five.png', 'm1'),
    ('36830000-0000-4000-8000-000000000006', '/content/asset-share-commons/en/details/stream.html/content/dam/synthetic/five.png', 'm1'),
    ('36830000-0000-4000-8000-000000000006', '/content/dam/synthetic/three.png', 'm1'),
    ('36830000-0000-4000-8000-000000000006', '/content/dam/synthetic/four.png', 'm1')
  ) v(cap, path, modified);

insert into plm.nbcu_property (capture_id, property_key, property_source_id, property_label,
  source_kind, source_url, source_captured_at, raw)
values ('36830000-0000-4000-8000-00000000000a', 'source-id:synthetic-p1', 'synthetic-p1', 'P1',
        'property', 'https://example.invalid', now(), '{}'::jsonb);

-- Refusals: not complete, complete with errors, unknown capture.
set local role service_role;
do $refusals$
declare v_id text;
begin
  foreach v_id in array array['36830000-0000-4000-8000-0000000000ff','36830000-0000-4000-8000-00000000000e'] loop
    begin
      perform plm.nbcu_publish_lifecycle(v_id::uuid);
      raise exception 'publish accepted an unqualified capture %', v_id;
    exception when sqlstate '22023' then null;
    end;
  end loop;
  begin
    perform plm.nbcu_publish_lifecycle('36830000-0000-4000-8000-00000000abcd');
    raise exception 'publish accepted an unknown capture';
  exception when sqlstate 'P0002' then null;
  end;
end
$refusals$;

-- A: bootstrap.
select plm.nbcu_publish_lifecycle('36830000-0000-4000-8000-00000000000a');
reset role;

do $bootstrap$
begin
  if (select mode from plm.nbcu_lifecycle_publication where capture_id = '36830000-0000-4000-8000-00000000000a') <> 'bootstrap' then
    raise exception 'first publication is not a bootstrap';
  end if;
  if not exists (select 1 from plm.nbcu_entity_lifecycle where entity_kind = 'asset'
                 and entity_key = '/content/dam/synthetic/one.png' and identity_basis = 'dam_path' and status = 'active') then
    raise exception 'details-viewer asset path was not normalized to its DAM path';
  end if;
  if (select count(*) from plm.nbcu_entity_lifecycle) <> 3 then
    raise exception 'bootstrap did not record exactly two assets and one property';
  end if;
  if not exists (select 1 from pg_locks where locktype = 'advisory' and pid = pg_backend_pid() and granted
                 and objsubid = 1
                 and ((classid::bigint << 32) | objid::bigint) = hashtextextended('plm.nbcu_publish_lifecycle', 0)) then
    raise exception 'publication did not hold its transaction advisory lock';
  end if;
end
$bootstrap$;

set local role service_role;
do $order$
begin
  begin
    perform plm.nbcu_publish_lifecycle('36830000-0000-4000-8000-00000000000a');
    raise exception 'publish accepted a capture twice';
  exception when unique_violation then null;
  end;
  begin
    perform plm.nbcu_publish_lifecycle('36830000-0000-4000-8000-000000000001');
    raise exception 'publish accepted an older capture';
  exception when sqlstate '22023' then null;
  end;
end
$order$;

-- B: comparable; two.png and P1 are withdrawn, one.png changes signal.
select plm.nbcu_publish_lifecycle('36830000-0000-4000-8000-00000000000b');
reset role;

do $comparable$
begin
  if (select mode from plm.nbcu_lifecycle_publication where capture_id = '36830000-0000-4000-8000-00000000000b') <> 'comparable' then
    raise exception 'same scope set did not compare';
  end if;
  if not exists (select 1 from plm.nbcu_entity_lifecycle where entity_key = '/content/dam/synthetic/two.png'
                 and status = 'withdrawn' and withdrawn_capture_id = '36830000-0000-4000-8000-00000000000b'
                 and first_withdrawn_at = '2026-09-02T00:00:00Z') then
    raise exception 'absent baseline asset was not withdrawn';
  end if;
  if not exists (select 1 from plm.nbcu_entity_lifecycle where entity_kind = 'property' and status = 'withdrawn') then
    raise exception 'absent baseline property was not withdrawn';
  end if;
  if not exists (select 1 from plm.nbcu_entity_lifecycle where entity_key = '/content/dam/synthetic/one.png'
                 and status = 'active' and last_changed_capture_id = '36830000-0000-4000-8000-00000000000b'
                 and first_seen_capture_id = '36830000-0000-4000-8000-00000000000a') then
    raise exception 'changed asset lost first sighting or change marker';
  end if;
end
$comparable$;

-- C: incompatible scope set; two.png reappears (reactivated), one.png is not withdrawn.
set local role service_role;
select plm.nbcu_publish_lifecycle('36830000-0000-4000-8000-00000000000c');
reset role;

do $rebaseline$
begin
  if (select mode from plm.nbcu_lifecycle_publication where capture_id = '36830000-0000-4000-8000-00000000000c') <> 'rebaseline' then
    raise exception 'different scope set was compared';
  end if;
  if not exists (select 1 from plm.nbcu_entity_lifecycle where entity_key = '/content/dam/synthetic/one.png' and status = 'active') then
    raise exception 'incomparable run withdrew an entity';
  end if;
  if not exists (select 1 from plm.nbcu_entity_lifecycle where entity_key = '/content/dam/synthetic/two.png'
                 and status = 'active' and withdrawn_at is null and first_withdrawn_at = '2026-09-02T00:00:00Z') then
    raise exception 'reappearing asset was not reactivated with its withdrawal history kept';
  end if;
end
$rebaseline$;

-- D: comparable with C but drops three of three baseline assets: held, nothing withdrawn.
set local role service_role;
select plm.nbcu_publish_lifecycle('36830000-0000-4000-8000-00000000000d');
reset role;

do $held$
begin
  if (select mode from plm.nbcu_lifecycle_publication where capture_id = '36830000-0000-4000-8000-00000000000d') <> 'withdrawal_held' then
    raise exception 'bulk drop was not held';
  end if;
  if exists (select 1 from plm.nbcu_entity_lifecycle where withdrawn_capture_id = '36830000-0000-4000-8000-00000000000d') then
    raise exception 'held publication withdrew an entity';
  end if;
  if not exists (select 1 from plm.nbcu_entity_lifecycle where entity_key = '/content/dam/synthetic/five.png' and status = 'active') then
    raise exception 'held publication did not record sightings';
  end if;
end
$held$;

-- Direct writes are refused for the loader role; withdrawal state is constrained.
-- After a held publication, the next comparable run re-evaluates the held drop instead
-- of orphaning it: /content/dam/synthetic/two.png was last seen before the hold and is now withdrawn.
set local role service_role;
select plm.nbcu_publish_lifecycle('36830000-0000-4000-8000-000000000006');
reset role;

do $after_hold$
begin
  if (select mode from plm.nbcu_lifecycle_publication where capture_id = '36830000-0000-4000-8000-000000000006') <> 'comparable' then
    raise exception 'run after a held publication did not compare';
  end if;
  if not exists (select 1 from plm.nbcu_entity_lifecycle where entity_key = '/content/dam/synthetic/two.png'
                 and status = 'withdrawn' and withdrawn_capture_id = '36830000-0000-4000-8000-000000000006') then
    raise exception 'drop held earlier was orphaned instead of re-evaluated';
  end if;
  if not exists (select 1 from plm.nbcu_entity_lifecycle where entity_key = '/content/dam/synthetic/five.png' and status = 'active') then
    raise exception 'entity seen after the hold is not active';
  end if;
end
$after_hold$;

-- Exact objects: column order and named constraints, not just names that resolve.
do $exact$
begin
  if (select string_agg(attname, ',' order by attnum) from pg_attribute
       where attrelid = 'plm.nbcu_entity_lifecycle'::regclass and attnum > 0 and not attisdropped)
     <> 'entity_kind,entity_key,identity_basis,first_seen_capture_id,first_seen_at,last_seen_capture_id,last_seen_at,last_changed_capture_id,change_signal,status,withdrawn_at,first_withdrawn_at,withdrawn_capture_id' then
    raise exception 'plm.nbcu_entity_lifecycle columns differ from the reviewed shape';
  end if;
  if (select string_agg(attname, ',' order by attnum) from pg_attribute
       where attrelid = 'plm.nbcu_lifecycle_publication'::regclass and attnum > 0 and not attisdropped)
     <> 'capture_id,baseline_capture_id,mode,derivation_contract,scope_sha256,source_captured_at,counts,published_at' then
    raise exception 'plm.nbcu_lifecycle_publication columns differ from the reviewed shape';
  end if;
  if (select count(*) from pg_constraint where conrelid = 'plm.nbcu_entity_lifecycle'::regclass
       and conname in ('nbcu_entity_lifecycle_pkey','nbcu_entity_lifecycle_kind_chk','nbcu_entity_lifecycle_status_chk',
                       'nbcu_entity_lifecycle_withdrawn_at_chk','nbcu_entity_lifecycle_history_chk')) <> 5
     or (select count(*) from pg_constraint where conrelid = 'plm.nbcu_entity_lifecycle'::regclass
          and contype = 'f' and confrelid = 'plm.nbcu_lifecycle_publication'::regclass) <> 4
     or (select count(*) from pg_constraint where conrelid = 'plm.nbcu_lifecycle_publication'::regclass
          and conname in ('nbcu_lifecycle_publication_pkey','nbcu_lifecycle_publication_mode_chk',
                          'nbcu_lifecycle_publication_baseline_chk','nbcu_lifecycle_publication_scope_chk')) <> 4 then
    raise exception 'durable-state constraints differ from the reviewed shape';
  end if;
  if not (select prosecdef from pg_proc where oid = 'plm.nbcu_publish_lifecycle(uuid)'::regprocedure) then
    raise exception 'publish function is not SECURITY DEFINER';
  end if;
end
$exact$;

set local role service_role;
do $direct$
begin
  begin
    delete from plm.nbcu_entity_lifecycle;
    raise exception 'service_role deleted lifecycle rows';
  exception when insufficient_privilege then null;
  end;
end
$direct$;
reset role;

do $constraint$
begin
  begin
    update plm.nbcu_entity_lifecycle set status = 'withdrawn' where entity_key = '/content/dam/synthetic/five.png';
    raise exception 'withdrawn status without a withdrawal time was accepted';
  exception when check_violation then null;
  end;
end
$constraint$;

rollback;
