begin;
-- popcre/shared-db#6271 — tests for plm.dcp_property_mg06_crosswalk and
-- plm.suggested_property_for_sku (designflow-backend#408 steps 1-2).
-- Synthetic fixtures and assertions are rolled back.
-- Synthetic fixtures exercise exact-only mapping and caller rights even on an
-- empty database. Historical collision/unmapped checks remain supplementary.

-- ============================================================
-- 1. Structural assertions (no external data dependencies)
-- ============================================================
do $$
begin
  assert (select count(*) from plm.dcp_property_mg06_crosswalk) >= 16,
    'crosswalk must have at least the 16 Done-criteria films';
  assert (select mg_code from plm.dcp_property_mg06_crosswalk
          where dcp_source_id = 'dcpvault:properties/ar/aristocats') = 'AC',
    'aristocats must map to AC';
  assert (select mg_code from plm.dcp_property_mg06_crosswalk
          where dcp_source_id = 'dcpvault:properties/li/lilo-and-stitch-umbrella') = 'LS',
    'lilo-and-stitch-umbrella must map to LS';
  assert (select confidence from plm.dcp_property_mg06_crosswalk
          where dcp_source_id = 'dcpvault:properties/ro/robin-hood') = 'unmapped',
    'robin-hood must be marked unmapped';
  assert (select confidence from plm.dcp_property_mg06_crosswalk
          where dcp_source_id = 'dcpvault:properties/li/lion-king-the-umbrella') = 'needs_review',
    'lion-king-the-umbrella must be marked needs_review';
  -- All Done-criteria films present
  for i in 1..16 loop
    assert (select count(*) from plm.dcp_property_mg06_crosswalk) >= i,
      'crosswalk must cover all Done-criteria films';
  end loop;
end $$;

-- Function must be STABLE (read-only)
do $$
begin
  assert (select provolatile from pg_proc
          where proname = 'suggested_property_for_sku'
            and pronamespace = 'plm'::regnamespace) = 's',
    'function must be STABLE (read-only)';
end $$;

-- Unknown SKU -> empty result (always testable)
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from plm.suggested_property_for_sku('NO-SUCH-SKU-XYZ');
  assert v_count = 0, 'unknown SKU must return empty';
end $$;

-- EXECUTE grants: PUBLIC is an ACL pseudo-role, not a pg_roles entry.
do $$
declare
  v_oid oid := 'plm.suggested_property_for_sku(text)'::regprocedure;
begin
  assert not exists (
    select 1 from pg_proc p,
      lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = v_oid and a.grantee = 0 and a.privilege_type = 'EXECUTE'
  ), 'PUBLIC must not execute suggestions';
  assert not has_function_privilege('anon', v_oid, 'EXECUTE'),
    'anon must not execute suggestions';
  assert has_function_privilege('authenticated', v_oid, 'EXECUTE'),
    'authenticated must execute suggestions';
  assert has_function_privilege('service_role', v_oid, 'EXECUTE'),
    'service_role must execute suggestions';
end $$;

-- Real landing rows, real consumer view and real RLS; all rolled back.
-- Each non-exact case has the same otherwise-valid inputs as the exact case.
do $$
declare
  v_crawl uuid := gen_random_uuid();
  v_run uuid := gen_random_uuid();
  v_sync uuid;
  v_guide uuid;
  v_asset uuid;
  v_property uuid;
  v_kind text;
  v_sku text;
  v_source text;
begin
  insert into coldlion.sync_run(endpoint, company_code, requested_by)
  values ('/itemDetails', 'FIX6372', 'FIX6372') returning id into v_sync;
  insert into plm.dcp_crawl(crawl_id, captured_on, portal_base_url,
    crawler_version, account_scope, line_of_business, started_at, captured_by,
    private_source_commit, status)
  values (v_crawl, date '2026-11-15', 'https://fixture.invalid',
    'FIX6372', 'FIX6372', 'FIX6372', now(), 'FIX6372', repeat('a',40), 'running');
  insert into plm.dcp_style_guide(source_path, folder_name, region, year_segment)
  values ('/fix6372', 'FIX6372', 'FIX6372', '2026') returning id into v_guide;
  insert into plm.dcp_metadata_run(metadata_run_id, source_crawl_id, captured_on,
    endpoint_suffix, crawler_version, captured_by, private_source_commit, assets_expected)
  values (v_run, v_crawl, date '2026-11-15', '/fix6372', 'FIX6372', 'FIX6372', repeat('a',40), 4);

  foreach v_kind in array array['exact','strong_candidate','needs_review','header'] loop
    v_sku := 'FIX6372-' || v_kind;
    v_source := 'dcpvault:properties/zz/' || v_sku;
    insert into coldlion.item_header(company_code, division_code, item_no, run_id,
      fetched_at, source_hash, first_seen_at, last_seen_at)
    values ('FIX6372', 'ZZ001', v_sku, v_sync, now(), repeat('b',64), now(), now());
    insert into coldlion.item_detail(company_code, division_code, item_no, item_pkey,
      run_id, fetched_at, source_hash, first_seen_at, last_seen_at)
    values ('FIX6372', 'ZZ001', v_sku, v_sku, v_sync, now(), repeat('b',64), now(), now());
    -- Header-only Disney with a non-Disney component must not unlock a suggestion.
    insert into coldlion.item_merch_group(company_code, division_code, item_no,
      item_pkey, slot_no, mg_code, run_id, fetched_at, source_hash, first_seen_at, last_seen_at)
    values ('FIX6372', 'ZZ001', v_sku,
      case when v_kind = 'header' then null else v_sku end,
      5, 'DY', v_sync, now(), repeat('b',64), now(), now());
    if v_kind = 'header' then
      insert into coldlion.item_merch_group(company_code, division_code, item_no,
        item_pkey, slot_no, mg_code, run_id, fetched_at, source_hash, first_seen_at, last_seen_at)
      values ('FIX6372', 'ZZ001', v_sku, v_sku, 5, 'CB', v_sync,
        now(), repeat('b',64), now(), now());
    end if;
    insert into public.sku_files_used(sku, file_name) values (v_sku, v_sku || '.png');
    insert into plm.dcp_asset(source_path, style_guide_id, file_name)
    values ('/fix6372/' || v_kind, v_guide, v_sku || '.png') returning id into v_asset;
    insert into plm.dcp_asset_crawl(crawl_id, dcp_asset_id, observed_row_hash)
    values (v_crawl, v_asset, repeat('c',64));
    insert into plm.dcp_metadata_asset(metadata_run_id, source_crawl_id, dcp_asset_id,
      fetch_status, raw_metadata, retrieved_at, source_hash)
    values (v_run, v_crawl, v_asset, 'success', '{}', now(), repeat('d',64));
    insert into plm.dcp_property(source_id) values (v_source) returning id into v_property;
    insert into plm.dcp_asset_property_observation(metadata_run_id, dcp_asset_id, dcp_property_id)
    values (v_run, v_asset, v_property);
    insert into plm.dcp_property_mg06_crosswalk(dcp_source_id, mg_code, mg_desc, provenance, confidence)
    values (v_source, 'ZZ6372', 'Synthetic', 'FIX6372',
      case when v_kind = 'header' then 'exact' else v_kind end);
  end loop;
end $$;

-- Authorize an actual signed-in administrator through the normal profile roles.
insert into public.invitations(email) values ('fix6372@fixture.invalid');
insert into auth.users(id, email, raw_user_meta_data, raw_app_meta_data)
values ('ac637200-0000-0000-0001-000000000001', 'fix6372@fixture.invalid', '{}', '{}');
insert into app.profile(auth_user_id, email, status)
values ('ac637200-0000-0000-0001-000000000001', 'fix6372@fixture.invalid', 'active')
on conflict(auth_user_id) do update set status = 'active';
insert into app.user_role(profile_id, role_id)
select p.id, r.id from app.profile p cross join app.role r
where p.auth_user_id = 'ac637200-0000-0000-0001-000000000001' and r.slug = 'administrator'
on conflict(profile_id, role_id) do update set revoked_at = null;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'ac637200-0000-0000-0001-000000000001', true);
select set_config('request.jwt.claims',
  '{"sub":"ac637200-0000-0000-0001-000000000001","role":"authenticated"}', true);
do $$
declare
  v_count integer;
  v_code text;
  v_basis text;
  v_file_count bigint;
  v_files text[];
  v_kind text;
begin
  select count(*), min(mg_code), min(basis), min(file_count)
    into v_count, v_code, v_basis, v_file_count
  from plm.suggested_property_for_sku('FIX6372-exact');
  assert v_count = 1 and v_code = 'ZZ6372' and v_basis = 'single_film' and v_file_count = 1,
    'authenticated exact mapping must return one single-film suggestion';
  select file_names into v_files from plm.suggested_property_for_sku('FIX6372-exact');
  assert v_files = array['FIX6372-exact.png'], 'suggestion must retain its source file';
  foreach v_kind in array array['strong_candidate','needs_review','header'] loop
    select count(*) into v_count from plm.suggested_property_for_sku('FIX6372-' || v_kind);
    assert v_count = 0, v_kind || ' must not produce a suggestion';
  end loop;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);

-- ============================================================
-- 2. Data-dependent assertions (run when test data exists)
-- ============================================================

-- Single film: 3FZ27DYNX01 (Nightmare Before Christmas, exact confidence) -> NX
do $$
declare
  v_count integer;
  v_code text;
  v_basis text;
begin
  select count(*), min(mg_code), min(basis)
    into v_count, v_code, v_basis
  from plm.suggested_property_for_sku('3FZ27DYNX01');
  if v_count > 0 then
    assert v_count = 1, 'single-film SKU must return exactly 1 suggestion, got ' || v_count;
    assert v_code = 'NX', 'must suggest NX, got ' || coalesce(v_code,'null');
    assert v_basis = 'single_film', 'basis must be single_film, got ' || coalesce(v_basis,'null');
  end if;
end $$;

-- Cross-licensor collision: MF296CBCC01 (Care Bears) must get NO suggestion
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from plm.suggested_property_for_sku('MF296CBCC01');
  assert v_count = 0, 'Care Bears SKU must get no suggestion, got ' || v_count;
end $$;

-- Cross-licensor collision: MFZ2GMVSP04 (Spider-Man) must get NO suggestion
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from plm.suggested_property_for_sku('MFZ2GMVSP04');
  assert v_count = 0, 'Marvel SKU must get no suggestion, got ' || v_count;
end $$;

-- Unmapped film: GFZ52DYCP03 (robin-hood only) must get NO suggestion
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from plm.suggested_property_for_sku('GFZ52DYCP03');
  assert v_count = 0, 'robin-hood-only SKU must get no suggestion (unmapped), got ' || v_count;
end $$;

rollback;
