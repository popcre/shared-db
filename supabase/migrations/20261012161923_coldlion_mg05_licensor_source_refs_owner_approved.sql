-- Issue #4235 (claim #4236): link the 38 owner-approved ColdLion MG05 Licensor source
-- identities to their existing canonical Licensors.
--
-- Why: production core.taxonomy_source_ref has no ColdLion Licensor identity at all, so
-- PopDAM licensing resolution (source key EDGEHOME/<division>/05/<code>) fails for every
-- licensed asset (u2giants/popdam3#357).
--
-- Authority: the owner-approved ColdLion mapping (Albert Hazan, approved 2026-08-18;
-- widened set hash 09e18e47d67181b06483d6cf4454e053, 552 mappings; private artifact).
-- Its Licensor subset is exactly the 19 codes below in CW001 and SP001 (38 rows, subset
-- hash b8e5cc3126a742eca1e8a5e0db4d8f57). Owner direction for this task, verbatim from
-- Albert's chat: "all licensing questions can be answered by the licensor scrapes."
--
-- What this does: INSERT provenance rows only. No canonical Licensor or Property row is
-- created, renamed, re-parented or re-statused (AGENTS.md 6.4 matched-row abstention).
-- MG06 Property identities are out of scope (issue #2541 replacement direction and the
-- 2026-09-25 owner HOLD remain untouched).
--
-- Fail-closed rules:
--   * an environment with none of the 19 canonical Licensors (CI shadow) is a no-op;
--     some-but-not-all present aborts;
--   * each canonical Licensor must carry exactly the approved code;
--   * an existing ColdLion source row for any of the 38 keys must already point at the
--     same canonical Licensor (idempotent), otherwise abort;
--   * after insert, the 38 keys must hash to the approved subset hash.

do $migration$
declare
  v_present integer;
  v_bad integer;
  v_hash text;
  v_count integer;
begin
  create temporary table issue_4235_approved(code text primary key, canonical_id uuid not null)
    on commit drop;
  insert into issue_4235_approved(code, canonical_id) values
      ('1P','f39fe07e-e438-46b2-9e17-fb711358e790'::uuid),
      ('AA','e90c3124-e66d-404f-b777-0dae9a5ee4f3'::uuid),
      ('CB','b96edc00-9261-46ec-af93-9de0f5b88d48'::uuid),
      ('CC','c70e095c-2baf-404e-a2a3-c198a259a3e6'::uuid),
      ('DC','33962356-f1f9-4226-b3ef-00154e5b7d56'::uuid),
      ('DY','7d141a6f-e229-46a2-b3f5-0ba0c97dd820'::uuid),
      ('HP','ea61e3bb-37f2-4cef-a6f4-8aa314ea131f'::uuid),
      ('MV','f143c083-2dfd-48b9-ac9b-43d2290a4e4c'::uuid),
      ('NB','154bf54b-6f7d-4999-b0fb-c2828b12b56a'::uuid),
      ('PN','afff41a6-df31-4a9a-aea5-b919d1daff54'::uuid),
      ('PP','a03fff4b-65f4-4fd6-98ad-c9db3216b140'::uuid),
      ('SE','e5f1686c-700c-42f6-bbc6-98aaa9ce1634'::uuid),
      ('SM','1619ecdc-a0ad-4d1e-b8f2-7ea2aa1184fb'::uuid),
      ('SS','4dba7d87-54ed-4dee-894b-570326953d92'::uuid),
      ('SW','14f2902d-42de-4820-83c5-e4f359a6e0d6'::uuid),
      ('VM','5f951f5e-aaee-4add-bb51-fea888951405'::uuid),
      ('WB','88313675-0089-4072-87be-5b989df8a3fc'::uuid),
      ('WW','7575d1db-dbee-4336-84a9-aa378f05f105'::uuid),
      ('ZZ','80276015-a751-4438-8c25-759c8dd005b2'::uuid);

  select count(*) into v_present
  from issue_4235_approved a join core.licensor l on l.id = a.canonical_id;
  if v_present = 0 then
    raise notice 'issue #4235: no approved canonical Licensor exists in this environment; no-op';
    return;
  end if;
  if v_present <> 19 then
    raise exception 'issue #4235: % of 19 approved canonical Licensors exist; refusing partial link', v_present;
  end if;

  select count(*) into v_bad
  from issue_4235_approved a join core.licensor l on l.id = a.canonical_id
  where btrim(coalesce(l.code, '')) <> a.code;
  if v_bad <> 0 then
    raise exception 'issue #4235: % approved Licensor(s) no longer carry the approved code; refusing', v_bad;
  end if;

  select count(*) into v_bad
  from issue_4235_approved a
  cross join (values ('CW001'), ('SP001')) d(division)
  join core.taxonomy_source_ref r
    on r.source_system = 'coldlion' and r.source_table = 'merchGroupDetails'
   and r.source_id = 'EDGEHOME/' || d.division || '/05/' || a.code
  where r.entity_schema <> 'core' or r.entity_table <> 'licensor' or r.entity_id <> a.canonical_id;
  if v_bad <> 0 then
    raise exception 'issue #4235: % existing ColdLion source row(s) conflict with the approved mapping; refusing', v_bad;
  end if;

  insert into core.taxonomy_source_ref(entity_schema, entity_table, entity_id, source_system,
    source_table, source_id, source_code, source_name, confidence, raw, first_seen_at, last_seen_at)
  select 'core', 'licensor', a.canonical_id, 'coldlion', 'merchGroupDetails',
    'EDGEHOME/' || d.division || '/05/' || a.code, a.code, l.name, 'verified',
    jsonb_build_object('implementation_issue', '#4235', 'consumer_issue', 'u2giants/popdam3#357',
      'approved_mapping_hash', '09e18e47d67181b06483d6cf4454e053',
      'approved_licensor_subset_hash', 'b8e5cc3126a742eca1e8a5e0db4d8f57'),
    now(), now()
  from issue_4235_approved a
  join core.licensor l on l.id = a.canonical_id
  cross join (values ('CW001'), ('SP001')) d(division)
  on conflict (source_system, source_table, source_id) do nothing;

  select count(*), md5(string_agg('licensor|' || r.source_id || '|' || r.entity_id::text, E'\n'
           order by ('licensor|' || r.source_id || '|' || r.entity_id::text) collate "C"))
    into v_count, v_hash
  from core.taxonomy_source_ref r
  join issue_4235_approved a on r.entity_id = a.canonical_id
  where r.source_system = 'coldlion' and r.source_table = 'merchGroupDetails'
    and r.entity_schema = 'core' and r.entity_table = 'licensor'
    and r.source_id in ('EDGEHOME/CW001/05/' || a.code, 'EDGEHOME/SP001/05/' || a.code);
  if v_count <> 38 or v_hash <> 'b8e5cc3126a742eca1e8a5e0db4d8f57' then
    raise exception 'issue #4235: post-insert set is % rows hash %, expected 38 / b8e5cc3126a742eca1e8a5e0db4d8f57',
      v_count, v_hash;
  end if;
end
$migration$;
