-- #3947: behavioral proof that Warner fallback twins are hidden and Sesame
-- brand generations collapse to one row per value_key.
--
-- HOW IT IS RUN
--   .github/workflows/database-contract-tests.yml executes every supabase/tests/*.sql
--   against a THROWAWAY local Supabase stack, wrapped in a single
--   `begin; ... \ir <file>; rollback;` transaction, as the migration owner.
--
-- EVERY VALUE IN THIS FILE IS INVENTED (ZZTEST- labels). The assertions CALL
-- api.db_data_admin_scraped_source_inventory as a Licensing principal and check
-- the returned rows; they do not string-search the function body.

do $$
declare
  v_profile uuid;
  v_auth uuid;
  v_role_id uuid;
  v_result jsonb;
  v_rows jsonb;
  v_capture_id uuid;
  v_sesame_capture_id uuid;
  v_warner_fallback_count integer := 0;
  v_warner_source_count integer := 0;
  v_sesame_count integer := 0;
  v_cursor text;
begin
  -- Licensing principal fixture.
  select p.id, p.auth_user_id into v_profile, v_auth
  from app.profile p
  where p.status = 'active' and p.auth_user_id is not null
  order by p.created_at, p.id limit 1;
  if v_profile is null then
    raise exception 'fixture requires an active authenticated profile';
  end if;
  select r.id into v_role_id from app.role r where r.slug = 'licensing'::app.app_role;
  delete from app.user_role where profile_id = v_profile and role_id = v_role_id;
  delete from app.app_access where profile_id = v_profile and app in ('plm', 'admin');
  insert into app.user_role (profile_id, role_id) values (v_profile, v_role_id);
  insert into app.app_access (profile_id, app) values (v_profile, 'plm');
  perform set_config('request.jwt.claim.sub', v_auth::text, true);

  -- Warner: create a capture header then a source_id row and its fallback twin.
  insert into plm.wb_capture
    (capture_id, chunk_number, target, status, captured_at,
     private_source_commit, snapshot_sha256, expected_row_count,
     captured_by, source_url, started_at)
  values
    (extensions.gen_random_uuid(), 0, 'warner_art_assets', 'loading', current_date,
     'zztest', 'zztest-sha256', 2,
     'zztest', 'https://example.invalid', now())
  returning capture_id into v_capture_id;

  insert into plm.wb_property
    (source_namespace, identity_method, source_id, fallback_key, label,
     capture_id, capture_chunk, source_url, raw, source_hash)
  values
    ('warner_art_assets', 'source_id', 'zztest-3947-src', null,
     'ZZTEST Warner Twin', v_capture_id, 0, 'https://example.invalid', '{}'::jsonb, 'zztest-hash-1'),
    ('warner_art_assets', 'natural_key_fallback', null, 'zztest-3947-fb',
     'ZZTEST Warner Twin', v_capture_id, 0, 'https://example.invalid', '{}'::jsonb, 'zztest-hash-2');

  -- Sesame: one value_key with both a legacy and a current generation row.
  insert into plm.sesame_capture
    (capture_key, source_repository, source_commit_sha, source_manifest_sha256,
     portal_base_url, portal_slug, source_captured_at, status, expected_counts)
  values
    ('zztest-3947-sesame', 'https://example.invalid', 'zztest', 'zztest',
     'https://example.invalid', 'zztest', now(), 'complete', '{}'::jsonb)
  returning id into v_sesame_capture_id;

  insert into plm.sesame_brand
    (capture_id, value_key, value_label, field_generation, asset_count, raw)
  values
    (v_sesame_capture_id, 'zztest 3947 sesame', 'zztest 3947 sesame', 'legacy', 1, '{}'::jsonb),
    (v_sesame_capture_id, 'zztest 3947 sesame', 'ZZTEST 3947 Sesame', 'current', 1, '{}'::jsonb);

  -- Walk the property inventory and count the synthetic rows.
  v_cursor := null;
  loop
    v_result := api.db_data_admin_scraped_source_inventory('property', 'ZZTEST', v_cursor, 1000);
    v_rows := coalesce(v_result -> 'rows', '[]'::jsonb);

    select count(*) into v_warner_fallback_count from jsonb_array_elements(v_rows) r
    where r ->> 'source_system' = 'warner_starlabs'
      and r ->> 'display_label' = 'ZZTEST Warner Twin'
      and r ->> 'source_id' like '%natural_key_fallback%';

    select count(*) into v_warner_source_count from jsonb_array_elements(v_rows) r
    where r ->> 'source_system' = 'warner_starlabs'
      and r ->> 'display_label' = 'ZZTEST Warner Twin'
      and r ->> 'source_id' like '%source_id%';

    select count(*) into v_sesame_count from jsonb_array_elements(v_rows) r
    where r ->> 'source_system' = 'sesame_thelettera_netx'
      and lower(r ->> 'display_label') like '%zztest 3947 sesame%';

    exit when v_warner_fallback_count > 0 or v_warner_source_count > 0 or v_sesame_count > 0
           or (v_result ->> 'next_cursor') is null;
    v_cursor := v_result ->> 'next_cursor';
  end loop;

  -- B1: The source_id twin is kept.
  if v_warner_source_count <> 1 then
    raise exception 'B1: expected 1 Warner source_id row for ZZTEST Warner Twin, got %', v_warner_source_count;
  end if;
  -- B2: The fallback twin is hidden.
  if v_warner_fallback_count <> 0 then
    raise exception 'B2: Warner fallback twin is still visible (count=%)', v_warner_fallback_count;
  end if;
  -- B3: Exactly one Sesame row survives (the current generation).
  if v_sesame_count <> 1 then
    raise exception 'B3: expected 1 Sesame row for ZZTEST 3947 Sesame, got %', v_sesame_count;
  end if;
end $$;

rollback;
