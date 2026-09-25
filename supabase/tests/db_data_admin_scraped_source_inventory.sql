begin;

-- Issue #2797: the raw scraped source inventory contract.
--
-- This proves the shape of api.db_data_admin_scraped_source_inventory without
-- reading a single licensed row: every assertion runs against the function
-- definition and the catalog, so no private source content can leak into public
-- CI evidence. It also proves that api.db_data_admin_scraped_properties, the
-- Property Matching contract, is still present and still separate.
--
-- A second block below exercises the function as a Licensing Manager and
-- asserts grouping behaviour (#3539) from response keys and counts only,
-- never row contents.

do $$
declare
  v_definition text;
  v_inventory_oid oid;
  v_required text;
  v_forbidden text;
  v_acl text;
begin
  select 'api.db_data_admin_scraped_source_inventory(text,text,text,integer)'::regprocedure
    into v_inventory_oid;
  select pg_get_functiondef(v_inventory_oid) into v_definition;

  -- ---------------------------------------------------------------------
  -- Representative all-licensor coverage across all three entity arms.
  -- ---------------------------------------------------------------------
  foreach v_required in array array[
    'Disney - Creative (DCP Vault)',
    'Disney - Submissions (OPA)',
    'Disney (Pixar) - Creative (DCP Vault)',
    'Disney (Pixar) - Submissions (OPA)',
    'Lucasfilm / Star Wars - Creative (DCP Vault)',
    'Lucasfilm / Star Wars - Submissions (OPA)',
    'DCP Vault - Creative (authoritative Marvel scope)',
    'DCP Vault - Creative (non-authoritative Marvel tag)',
    'Marvel - Submissions (OPA)',
    'Marvel - Creative (ASGARD)',
    '20th Century - Creative (DCP Vault)',
    'Warner Bros. - Creative (STARLABS)',
    'NBCUniversal - Creative (Creative Asset Factory)',
    'Paramount - Creative (Creative Library)',
    'Paramount - Submissions (TrackerPlus)',
    'Sega - Creative',
    'Sega - Submissions',
    'Strawberry Shortcake - Creative',
    'Coca-Cola - Creative (Asset Library Property choices)',
    'Peanuts - Creative (Tenovos)',
    'Sesame Workshop - Creative (NetX)',
    'WWE - Creative',
    'WWE - Submissions'
  ] loop
    if position(v_required in v_definition) = 0 then
      raise exception 'required inventory licensor heading is absent: %', v_required;
    end if;
  end loop;

  -- ---------------------------------------------------------------------
  -- Disney (including Pixar) and the other licensors stay separate groups,
  -- decided by scrape route and source authority, never by name similarity.
  -- ---------------------------------------------------------------------
  foreach v_required in array array[
    '''disney''',
    '''pixar''',
    '''lucasfilm-star-wars''',
    '''marvel-asgard-creative''',
    '''dcp-vault-non-authoritative-marvel-tag''',
    '''20th-century'''
  ] loop
    if position(v_required in v_definition) = 0 then
      raise exception 'required distinct licensor key is absent: %', v_required;
    end if;
  end loop;

  -- ---------------------------------------------------------------------
  -- Issue #2905: one canonical licensor group per row across both purposes,
  -- in every entity arm, with a single trailing unresolved group.
  -- ---------------------------------------------------------------------
  if (length(v_definition) - length(replace(v_definition,
        'end::text as licensor_group_key', ''))) / length('end::text as licensor_group_key') <> 3
     or (length(v_definition) - length(replace(v_definition,
        '''licensor_group_key'', n.licensor_group_key', ''))) / length('''licensor_group_key'', n.licensor_group_key') <> 3
     or (length(v_definition) - length(replace(v_definition,
        '''licensor_group_name'', n.licensor_group_name', ''))) / length('''licensor_group_name'', n.licensor_group_name') <> 3 then
    raise exception 'every inventory arm must emit licensor_group_key and licensor_group_name';
  end if;

  foreach v_required in array array[
    'else ''unresolved''',
    'else ''Licensor not yet determined''',
    'when s.licensor_key in (''marvel'', ''marvel-opa'', ''marvel-asgard-creative'') then ''marvel''',
    'when s.licensor_key in (''disney'', ''disney-opa'') then ''disney''',
    'when s.licensor_key in (''lucasfilm-star-wars'', ''lucasfilm-star-wars-opa'') then ''lucasfilm-star-wars''',
    'when s.source_system = ''disney_dcpvault'' then ''disney''',
    'when s.source_system = ''marvel_dcpvault'' then ''marvel''',
    'when s.source_system = ''lucasfilm_dcpvault'' then ''lucasfilm-star-wars''',
    'when s.source_system = ''twentieth_century_dcpvault'' then ''20th-century''',
    'when p.source_kind in (''property'', ''franchise_asset'')',
    'NBCUniversal - Submissions (Product Submissions picker)'
  ] loop
    if position(v_required in v_definition) = 0 then
      raise exception 'canonical licensor grouping clause is absent: %', v_required;
    end if;
  end loop;

  -- Unresolved and conflict keys must never be mapped to a real licensor group.
  foreach v_forbidden in array array[
    'opa-scope-conflict'', ''disney',
    '''disney-opa-unresolved'') then',
    '''dcp-vault-non-authoritative-marvel-tag'') then',
    '''dcp-authority-conflict'') then'
  ] loop
    if position(v_forbidden in v_definition) <> 0 then
      raise exception 'an unresolved licensor key is assigned to a real licensor group: %', v_forbidden;
    end if;
  end loop;

  -- ---------------------------------------------------------------------
  -- Both source purposes are normalized to exactly Creative or Submissions.
  -- ---------------------------------------------------------------------
  if position('''Creative''' in v_definition) = 0
     or position('''Submissions''' in v_definition) = 0 then
    raise exception 'inventory does not normalize source purpose to Creative and Submissions';
  end if;

  -- ---------------------------------------------------------------------
  -- Inventory only. No matching controls, review classifications, contract
  -- status, authority-derived presentation buckets, or asset context.
  -- ---------------------------------------------------------------------
  foreach v_forbidden in array array[
    'review_reason',
    'evidence_basis',
    'review_guidance',
    'contract_status',
    'asset_count',
    'style_guide_names'
  ] loop
    if position(v_forbidden in v_definition) <> 0 then
      raise exception 'inventory leaks a review or matching field: %', v_forbidden;
    end if;
  end loop;

  -- ---------------------------------------------------------------------
  -- Non-authoritative inferred candidate tables are never presented as a
  -- source-declared claim the licensor never made.
  -- ---------------------------------------------------------------------
  foreach v_forbidden in array array[
    'sega_character_candidate',
    'sega_style_guide_candidate',
    'wwe_character_candidate'
  ] loop
    if position(v_forbidden in v_definition) <> 0 then
      raise exception 'inventory presents an inferred candidate table as source-declared: %', v_forbidden;
    end if;
  end loop;

  -- ---------------------------------------------------------------------
  -- Stable identity: every entity arm keys on source system and source table,
  -- so bare integer source ids cannot collide across licensors.
  -- ---------------------------------------------------------------------
  foreach v_required in array array[
    '''property'', s.licensor_key, s.source_system, s.source_table, s.source_id',
    '''character'', s.licensor_key, s.source_system, s.source_table, s.source_id',
    '''style_guide'', s.licensor_key, s.source_system, s.source_table, s.source_id'
  ] loop
    if position(v_required in v_definition) = 0 then
      raise exception 'entity arm lacks a source-system-qualified stable row key: %', v_required;
    end if;
  end loop;

  -- ---------------------------------------------------------------------
  -- Entity-kind validation, deterministic keyset paging, bounded page size.
  -- ---------------------------------------------------------------------
  if position('not in (''property'', ''character'', ''style_guide'')' in v_definition) = 0
     or position('db_data_admin: invalid entity kind' in v_definition) = 0 then
    raise exception 'inventory does not validate the entity kind';
  end if;

  if position('least(greatest(coalesce(p_page_size, 500), 1), 1000)' in v_definition) = 0 then
    raise exception 'inventory page size is not clamped to 1..1000';
  end if;

  if position('db_data_admin: invalid cursor' in v_definition) = 0
     or position('decode(p_cursor, ''base64'')' in v_definition) = 0
     or position('collate "C" > v_cursor_key' in v_definition) = 0 then
    raise exception 'inventory paging is not a validated deterministic keyset walk';
  end if;

  if position('p_search' in v_definition) = 0 then
    raise exception 'inventory does not accept search text';
  end if;

  -- ---------------------------------------------------------------------
  -- Security: Licensing Manager gate, security definer, pinned search path,
  -- authenticated-only execution.
  -- ---------------------------------------------------------------------
  if position('app.require_licensing_manager_access()' in v_definition) = 0 then
    raise exception 'inventory does not enforce the Licensing Manager gate';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.oid = v_inventory_oid and p.prosecdef and p.provolatile = 's'
  ) then
    raise exception 'inventory is not a stable security definer function';
  end if;

  if not exists (
    select 1 from pg_proc p
    where p.oid = v_inventory_oid
      and p.proconfig @> array['search_path=app, public']
  ) then
    raise exception 'inventory does not pin search_path to app, public';
  end if;

  select array_to_string(p.proacl, ' ') into v_acl
  from pg_proc p where p.oid = v_inventory_oid;

  if v_acl is null or position('authenticated=X' in v_acl) = 0 then
    raise exception 'inventory does not grant execute to authenticated';
  end if;

  if position('=X/' in v_acl) <> 0
     and (position('anon=X' in v_acl) <> 0
       or position('service_role=X' in v_acl) <> 0
       or v_acl like '%,=X%' or v_acl like '{=X%') then
    raise exception 'inventory execute is not restricted to authenticated: %', v_acl;
  end if;

  -- ---------------------------------------------------------------------
  -- The Property Matching contract is untouched and remains separate.
  -- ---------------------------------------------------------------------
  if to_regprocedure('api.db_data_admin_scraped_properties(text,text,integer)') is null then
    raise exception 'the existing Property Matching RPC is missing';
  end if;

  if position('review_reason' in pg_get_functiondef(
       'api.db_data_admin_scraped_properties(text,text,integer)'::regprocedure)) = 0 then
    raise exception 'the existing Property Matching RPC lost its review fields';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Behavioural proof (#3539): call the inventory and assert grouping from
-- response keys and counts only. Pixar rows must group under Disney; zero
-- *_dcpvault rows may land in the unresolved group; disney_dcpvault rows
-- positively group to disney.
-- ---------------------------------------------------------------------
do $$
declare
  v_profile uuid;
  v_auth uuid;
  v_role_id uuid;
  v_kind text;
  v_cursor text;
  v_result jsonb;
begin
  select p.id, p.auth_user_id into v_profile, v_auth
  from app.profile p
  where p.status = 'active' and p.auth_user_id is not null
  order by p.created_at, p.id limit 1;
  if v_profile is null then
    raise exception 'behavioural fixture requires an active authenticated profile';
  end if;

  select r.id into v_role_id from app.role r where r.slug = 'licensing'::app.app_role;
  delete from app.user_role where profile_id = v_profile and role_id = v_role_id;
  delete from app.app_access where profile_id = v_profile and app in ('plm', 'admin');
  insert into app.user_role (profile_id, role_id) values (v_profile, v_role_id);
  insert into app.app_access (profile_id, app) values (v_profile, 'plm');
  perform set_config('request.jwt.claim.sub', v_auth::text, true);

  foreach v_kind in array array['property', 'character', 'style_guide'] loop
    v_cursor := null;
    loop
      v_result := api.db_data_admin_scraped_source_inventory(v_kind, null, v_cursor, 1000);
      if v_result is null or jsonb_typeof(v_result) <> 'object' then
        raise exception 'inventory arm % returned no object', v_kind;
      end if;

      -- (a) Pixar is never its own licensor group.
      if exists (
        select 1 from jsonb_array_elements(v_result -> 'rows') r
        where r ->> 'licensor_group_key' = 'pixar'
           or r ->> 'licensor_group_name' = 'Pixar'
      ) then
        raise exception 'entity kind % returns a pixar licensor group', v_kind;
      end if;

      -- (b) Zero *_dcpvault rows in the unresolved group.
      if exists (
        select 1 from jsonb_array_elements(v_result -> 'rows') r
        where r ->> 'source_system' in (
            'disney_dcpvault', 'marvel_dcpvault',
            'lucasfilm_dcpvault', 'twentieth_century_dcpvault')
          and r ->> 'licensor_group_key' = 'unresolved'
      ) then
        raise exception 'entity kind % returns a *_dcpvault row in the unresolved group', v_kind;
      end if;

      -- (c) Positive control: disney_dcpvault groups to disney.
      if exists (
        select 1 from jsonb_array_elements(v_result -> 'rows') r
        where r ->> 'source_system' = 'disney_dcpvault'
          and r ->> 'licensor_group_key' <> 'disney'
      ) then
        raise exception 'entity kind % returns a disney_dcpvault row outside the disney group', v_kind;
      end if;

      v_cursor := v_result ->> 'next_cursor';
      exit when v_cursor is null;
    end loop;
  end loop;
end $$;

rollback;
