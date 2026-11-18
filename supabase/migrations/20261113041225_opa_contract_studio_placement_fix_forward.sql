-- Issue #2541 / #6228: repair only the two reviewed OPA identity links.
-- Standard Characters (OPA 361) and X-Men Classic remain intact. Reuse an
-- unambiguous exact canonical target, or create it with licensing authority.
-- The DO block is atomic: a failed assertion rolls back every repair.
-- derived-from: 20261112225250

do $fix_forward_2541$
declare
  v_actor constant text := 'shared-db migration 20261113041225';
  r record;
  v_lic uuid;
  v_id uuid;
  v_previous uuid;
  v_n integer;
  v_updated timestamptz;
begin
  if to_regclass('core.property') is null or to_regclass('plm.opa_property') is null then
    raise notice '#2541 fix-forward: landing absent; nothing to do';
    return;
  end if;

  -- Serialize identity lookup/create and link replacement, including retries.
  lock table core.property, core.taxonomy_source_ref, plm.source_resolution
    in share row exclusive mode;

  for r in
    select * from (values
      ('372', 'Standard Characters', 'Mickey Mouse', 'disney', 'DY'),
      ('640', 'X-Men Classic', 'X-Men', 'marvel', 'MV')
    ) as repairs(k, previous_name, canonical_name, studio, licensor_code)
  loop
    -- An empty landing is normal in schema-only rehearsals.
    if not exists (select 1 from plm.opa_property where licensed_property_id::text = r.k) then
      continue;
    end if;
    if not exists (
      select 1 from plm.opa_property o
      join plm.opa_property_studio_resolution s using (licensed_property_id)
      where o.licensed_property_id::text = r.k and o.property_name = r.canonical_name
        and s.resolution_status = 'canonical' and s.studio_code = r.studio
    ) then
      raise exception '#2541 fix-forward: unexpected submission or studio for OPA %', r.k;
    end if;
    select count(*), min(id::text)::uuid into v_n, v_lic
      from core.licensor where code = r.licensor_code;
    if v_n <> 1 then
      raise exception '#2541 fix-forward: expected one studio licensor for OPA %', r.k;
    end if;

    v_previous := null;
    select entity_id into v_previous from core.taxonomy_source_ref
      where source_system = 'disney_opa' and source_table = 'plm.opa_property' and source_id = r.k;
    if v_previous is not null and not exists (
      select 1 from core.taxonomy_source_ref t join core.property p on p.id = t.entity_id
      where t.source_system = 'disney_opa' and t.source_table = 'plm.opa_property' and t.source_id = r.k
        and t.entity_schema = 'core' and t.entity_table = 'property'
        and p.licensor_id = v_lic and p.name in (r.previous_name, r.canonical_name)
    ) then
      raise exception '#2541 fix-forward: unexpected previous identity or outside studio licensor for OPA %', r.k;
    end if;

    select count(*), min(id::text)::uuid into v_n, v_id from core.property
      where licensor_id = v_lic and lower(name) = lower(r.canonical_name);
    if v_n > 1 then
      raise exception '#2541 fix-forward: duplicate canonical targets for OPA %', r.k;
    end if;
    if v_id is not null and not exists (
      select 1 from core.property where id = v_id and name = r.canonical_name
    ) then
      raise exception '#2541 fix-forward: canonical target spelling differs for OPA %', r.k;
    end if;
    if exists (
      select 1 from plm.source_resolution sr
      left join core.property p on p.id = sr.core_property_id
      where sr.source_system = 'disney_opa' and sr.entity_kind = 'property' and sr.source_id = r.k
        and (sr.resolution_status <> 'matched' or p.id is null
          or p.licensor_id <> v_lic or p.name not in (r.previous_name, r.canonical_name))
    ) then
      raise exception '#2541 fix-forward: unexpected source resolution for OPA %', r.k;
    end if;
    if v_id is null then
      insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
      values (pg_backend_pid(), txid_current(), 'core.property', 'licensing_review_create', gen_random_uuid(),
        encode(extensions.digest('2541/fix-forward/create/'||r.k,'sha256'),'hex'), v_actor,
        array['licensor_id','name','code','status'], clock_timestamp() + interval '1 minute');
      insert into core.property(licensor_id,name,code,status,metadata)
      values (v_lic, r.canonical_name, null, 'potential', jsonb_build_object(
        'authorising_issue',2541,'migration','20261113041225','source_system','disney_opa',
        'licensed_property_id',r.k,'fix_forward',true)) returning id into v_id;
    end if;

    insert into core.taxonomy_source_ref(entity_schema,entity_table,entity_id,source_system,source_table,source_id,source_name,confidence,raw)
    values ('core','property',v_id,'disney_opa','plm.opa_property',r.k,r.canonical_name,'verified',
      jsonb_build_object('authorising_issue',2541,'migration','20261113041225','fix_forward',true))
    on conflict (source_system,source_table,source_id) do update
      set entity_id = excluded.entity_id, source_name = excluded.source_name,
          confidence = excluded.confidence,
          raw = core.taxonomy_source_ref.raw || excluded.raw;

    v_updated := null;
    select updated_at into v_updated from plm.source_resolution
      where source_system = 'disney_opa' and entity_kind = 'property' and source_id = r.k;
    perform plm.set_source_resolution('disney_opa'::text, 'property'::text, r.k, 'matched'::text,
      v_id, null::uuid, null::uuid, null::uuid,
      '#2541 / #6228 repair OPA identity link'::text, v_updated);
  end loop;

  -- Post-condition: every studio-placed OPA property chain is now complete.
  declare v_n integer; v_expected integer;
  begin
    select count(*) into v_expected
      from plm.opa_property o join plm.opa_property_studio_resolution s using (licensed_property_id)
     where s.resolution_status = 'canonical';
    select count(*) into v_n
      from plm.opa_property o
      join plm.opa_property_studio_resolution s using (licensed_property_id)
      join core.taxonomy_source_ref t on t.source_system='disney_opa' and t.source_table='plm.opa_property'
           and t.source_id = o.licensed_property_id::text
      join core.property p on p.id = t.entity_id and p.name = o.property_name
      join core.licensor l on l.id = p.licensor_id
           and l.code = case s.studio_code when 'marvel' then 'MV' when 'lucasfilm' then 'SW' else 'DY' end
      join plm.source_resolution sr on sr.source_system='disney_opa' and sr.entity_kind='property'
           and sr.source_id = o.licensed_property_id::text and sr.resolution_status='matched' and sr.core_property_id = p.id
     where s.resolution_status = 'canonical';
    if v_n <> v_expected then
      raise exception '#2541 fix-forward post-condition: % of % studio-placed OPA properties are canonical', v_n, v_expected;
    end if;
  end;
end
$fix_forward_2541$;
