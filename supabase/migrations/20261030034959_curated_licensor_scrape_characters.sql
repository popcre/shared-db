-- Issue popcre/shared-db#5079 (claim #5082): canonical Characters from the authorized
-- licensor portal scrapes, with licensor ownership, source provenance and the direct
-- Property links the source itself publishes.
--
-- Owner ruling, Albert Hazan, 2026-10-29 (verbatim): "forget the designflow character
-- lost, that was nonsense. licensor scrape is authoritative." No DesignFlow list is read.
--
-- NO LICENSED VALUES ARE IN THIS FILE. Every name is read inside the database from the
-- plm.* capture tables.
--
-- SOURCES (docs/core-character-backfill-source-decision-20260902.md sec.3, and the
-- source-family licensor scopes in config/db-data-admin-property-source-coverage.json):
--   disney_opa                  plm.opa_character            licensor by OPA studio evidence
--   warner_starlabs             plm.wb_character_normalized  WB  (Warner Bros.)
--   nbcu_creative_asset_factory plm.nbcu_character           NB  (NBCUniversal)
--   paramount_creative_library  plm.pmt_character            VM  (Paramount = VM, ruling 2026-09-06)
--   wildbrain_tenovos           plm.wildbrain_character      SS  (Strawberry Shortcake / WildBrain)
--
-- EXCLUDED, fail closed:
--   * Peanuts / Sesame: asset-tag facet dictionaries, not identity registers (sec.3 Tier 3).
--   * Sega / WWE: inferred candidates by construction (sec.3 Tier 3).
--   * Marvel ASGARD: resolves only through plm.marvel_asgard_character_opa_resolution into
--     the OPA identity space (sec.3); that table holds no resolution, so nothing is promoted twice.
--   * Marvel DCP: mixed-guide raw evidence (business-rules/licensing-master-data.md).
--   * Disney DCP and "Lucasfilm" DCP: every display_name is empty (slug only), and the
--     Lucasfilm DCP table carries non-Lucasfilm (Pixar) slugs, so a name or a licensor
--     would have to be invented.
--   * WildBrain values not in the source dictionary (observed-only labels).
--
-- OPA LICENSOR. OPA is multi-studio. A character's licensor is taken from the canonical
-- studio evidence (plm.opa_property_studio_resolution, resolution_status 'canonical') of
-- the Properties OPA itself links it to: disney -> DY, pixar -> DY (presented as
-- "Disney (Pixar)", migration 20261007020907), marvel -> MV, lucasfilm -> SW (three
-- separate Licensors, ruling 2026-09-14). A character whose evidence names more than one
-- licensor, or none, is not promoted.
--
-- IDENTITY. licensor + source id, never the source id alone (sec.4): code is
-- '<source_system>:<source id>' under the owning licensor, unique on (licensor_id, code).
-- Every character gets one core.taxonomy_source_ref keyed on its exact source identity.
-- core.character was empty when this was written, so every row is a genuinely new row
-- (owner-rulings 6.4 new-row allowance); nothing matched is updated.
--
-- PROPERTY LINKS. Only where the scrape publishes the Property/Character edge directly
-- (plm.opa_property_character) AND that source Property is already resolved to a
-- core.property through core.taxonomy_source_ref, under the same licensor. Never by name
-- ("similar names are never a mapping", ruling 2026-10-11). Each link is a current
-- direct_source_assertion support edge plus its canonical association row.
--
-- Idempotent: a rerun inserts nothing.

do $characters$
declare
  v_issue constant text := 'popcre/shared-db#5079';
  v_actor constant text := 'shared-db migration 20261030034959';
  v_dy uuid; v_mv uuid; v_sw uuid; v_wb uuid; v_nb uuid; v_vm uuid; v_ss uuid;
  v_n integer;
  v_expected integer;
begin
  select id into v_dy from core.licensor where code = 'DY';
  select id into v_mv from core.licensor where code = 'MV';
  select id into v_sw from core.licensor where code = 'SW';
  select id into v_wb from core.licensor where code = 'WB';
  select id into v_nb from core.licensor where code = 'NB';
  select id into v_vm from core.licensor where code = 'VM';
  select id into v_ss from core.licensor where code = 'SS';
  if v_dy is null or v_mv is null or v_sw is null or v_wb is null or v_nb is null or v_vm is null or v_ss is null then
    raise exception '#5079: a required licensor (DY, MV, SW, WB, NB, VM, SS) is missing';
  end if;

  -- ------------------------------------------------------------------ Disney OPA
  -- (DY, MV, SW: one licensor per character from canonical studio evidence)
  insert into core.character (licensor_id, name, code, status, metadata)
  select a.licensor_id, btrim(c.character_name), 'disney_opa:' || c.character_id::text, 'active',
         jsonb_build_object('source_system', 'disney_opa', 'source_table', 'plm.opa_character',
                            'source_id', c.character_id::text, 'loaded_by', v_actor, 'issue', v_issue)
    from plm.opa_character c
    join (select pc.character_id,
                 min(case when r.studio_code in ('disney', 'pixar') then v_dy::text
                          when r.studio_code = 'marvel' then v_mv::text else v_sw::text end)::uuid as licensor_id
            from plm.opa_property_character pc
            join plm.opa_property_studio_resolution r
              on r.licensed_property_id = pc.licensed_property_id and r.resolution_status = 'canonical'
           where r.studio_code in ('disney', 'pixar', 'marvel', 'lucasfilm')
           group by pc.character_id
          having count(distinct case when r.studio_code in ('disney', 'pixar') then 'DY'
                                     when r.studio_code = 'marvel' then 'MV' else 'SW' end) = 1) a
      on a.character_id = c.character_id
   where nullif(btrim(c.character_name), '') is not null
  on conflict do nothing;

  -- --------------------------------------------------------------- Warner (WB)
  insert into core.character (licensor_id, name, code, status, metadata)
  select v_wb, btrim(w.label),
         'warner_starlabs:' || w.source_namespace || ':' || coalesce(w.source_id, w.fallback_key), 'active',
         jsonb_build_object('source_system', 'warner_starlabs', 'source_table', 'plm.wb_character_normalized',
                            'source_id', w.source_namespace || ':' || coalesce(w.source_id, w.fallback_key),
                            'identity_method', w.identity_method, 'loaded_by', v_actor, 'issue', v_issue)
    from plm.wb_character_normalized w
   where w.status = 'active' and nullif(btrim(w.label), '') is not null
     and coalesce(w.source_id, w.fallback_key) is not null
  on conflict do nothing;

  -- ----------------------------------------------------------------- NBCU (NB)
  insert into core.character (licensor_id, name, code, status, metadata)
  select v_nb, n.label, 'nbcu_creative_asset_factory:' || n.character_key, 'active',
         jsonb_build_object('source_system', 'nbcu_creative_asset_factory', 'source_table', 'plm.nbcu_character',
                            'source_id', n.character_key, 'loaded_by', v_actor, 'issue', v_issue)
    from (select character_key, min(btrim(character_label)) as label
            from plm.nbcu_character group by character_key) n
   where nullif(n.label, '') is not null
  on conflict do nothing;

  -- ------------------------------------------------- Paramount Creative Library (VM)
  insert into core.character (licensor_id, name, code, status, metadata)
  select v_vm, p.label, 'paramount_creative_library:' || p.character_source_id, 'active',
         jsonb_build_object('source_system', 'paramount_creative_library', 'source_table', 'plm.pmt_character',
                            'source_id', p.character_source_id, 'loaded_by', v_actor, 'issue', v_issue)
    from (select character_source_id::text as character_source_id, min(btrim(character_name)) as label
            from plm.pmt_character group by 1) p
   where nullif(p.label, '') is not null
  on conflict do nothing;

  -- -------------------------------------------------------------- WildBrain (SS)
  insert into core.character (licensor_id, name, code, status, metadata)
  select v_ss, b.label, 'wildbrain_tenovos:' || b.character_source_id, 'active',
         jsonb_build_object('source_system', 'wildbrain_tenovos', 'source_table', 'plm.wildbrain_character',
                            'source_id', b.character_source_id, 'loaded_by', v_actor, 'issue', v_issue)
    from (select character_source_id::text as character_source_id, min(btrim(character_label)) as label
            from plm.wildbrain_character where in_source_dictionary group by 1) b
   where nullif(b.label, '') is not null
  on conflict do nothing;

  -- --------------------------------------------------------------- provenance
  -- One source ref per character, keyed on its exact source identity. The identity guard
  -- derives and stamps source_licensor_id from the character itself.
  insert into core.taxonomy_source_ref
    (entity_schema, entity_table, entity_id, source_system, source_table, source_id, source_name, confidence, raw)
  select 'core', 'character', ch.id, ch.metadata ->> 'source_system', ch.metadata ->> 'source_table',
         ch.metadata ->> 'source_id', ch.name, 1, jsonb_build_object('loaded_by', v_actor, 'issue', v_issue)
    from core.character ch
   where ch.metadata ->> 'issue' = v_issue
  on conflict (source_system, source_table, source_id) do nothing;

  -- ------------------------------------------------- direct OPA Property links
  insert into core.property_character_source_edge
    (property_id, character_id, licensor_id, source_system, source_id, source_evidence, evidence_kind,
     is_direct_source_relationship, observation_count, confidence, is_current, metadata, created_by, updated_by)
  select distinct pr.entity_id, ch.id, ch.licensor_id, 'disney_opa',
         pc.licensed_property_id::text || ':' || pc.character_id::text,
         'plm.opa_property_character', 'direct_source_assertion', true, 0, null, true,
         jsonb_build_object('loaded_by', v_actor, 'issue', v_issue), v_actor, v_actor
    from plm.opa_property_character pc
    join core.character ch
      on ch.code = 'disney_opa:' || pc.character_id::text and ch.metadata ->> 'issue' = v_issue
    join core.taxonomy_source_ref pr
      on pr.source_system = 'disney_opa' and pr.source_table = 'plm.opa_property'
     and pr.entity_schema = 'core' and pr.entity_table = 'property'
     and pr.source_id = pc.licensed_property_id::text
    join core.property p on p.id = pr.entity_id and p.licensor_id = ch.licensor_id
   where not exists (select 1 from core.property_character_source_edge e
                      where e.property_id = pr.entity_id and e.character_id = ch.id
                        and e.licensor_id = ch.licensor_id and e.source_system = 'disney_opa'
                        and e.evidence_kind = 'direct_source_assertion' and e.is_current);

  insert into core.property_character_associations (property_id, character_id, is_current)
  select distinct e.property_id, e.character_id, true
    from core.property_character_source_edge e
   where e.metadata ->> 'issue' = v_issue and e.is_current
  on conflict (property_id, character_id) do nothing;

  -- ------------------------------------------------------------- self-checks
  -- Each licensor's loaded count must equal its eligible source identities.
  select count(*) into v_expected from (
    select pc.character_id
      from plm.opa_property_character pc
      join plm.opa_property_studio_resolution r
        on r.licensed_property_id = pc.licensed_property_id and r.resolution_status = 'canonical'
      join plm.opa_character c on c.character_id = pc.character_id and nullif(btrim(c.character_name), '') is not null
     where r.studio_code in ('disney', 'pixar', 'marvel', 'lucasfilm')
     group by pc.character_id
    having count(distinct case when r.studio_code in ('disney', 'pixar') then 'DY'
                               when r.studio_code = 'marvel' then 'MV' else 'SW' end) = 1) x;
  select count(*) into v_n from core.character where metadata ->> 'source_system' = 'disney_opa';
  if v_n <> v_expected then raise exception '#5079 OPA: % characters loaded, % eligible', v_n, v_expected; end if;

  select count(*) into v_expected from plm.wb_character_normalized
   where status = 'active' and nullif(btrim(label), '') is not null and coalesce(source_id, fallback_key) is not null;
  select count(*) into v_n from core.character where licensor_id = v_wb and metadata ->> 'source_system' = 'warner_starlabs';
  if v_n <> v_expected then raise exception '#5079 WB: % characters loaded, % eligible', v_n, v_expected; end if;

  select count(distinct character_key) into v_expected from plm.nbcu_character where nullif(btrim(character_label), '') is not null;
  select count(*) into v_n from core.character where licensor_id = v_nb and metadata ->> 'source_system' = 'nbcu_creative_asset_factory';
  if v_n <> v_expected then raise exception '#5079 NB: % characters loaded, % eligible', v_n, v_expected; end if;

  select count(distinct character_source_id) into v_expected from plm.pmt_character where nullif(btrim(character_name), '') is not null;
  select count(*) into v_n from core.character where licensor_id = v_vm and metadata ->> 'source_system' = 'paramount_creative_library';
  if v_n <> v_expected then raise exception '#5079 VM: % characters loaded, % eligible', v_n, v_expected; end if;

  select count(distinct character_source_id) into v_expected from plm.wildbrain_character
   where in_source_dictionary and nullif(btrim(character_label), '') is not null;
  select count(*) into v_n from core.character where licensor_id = v_ss and metadata ->> 'source_system' = 'wildbrain_tenovos';
  if v_n <> v_expected then raise exception '#5079 SS: % characters loaded, % eligible', v_n, v_expected; end if;

  select count(*) into v_n from core.character ch
   where ch.metadata ->> 'issue' = v_issue
     and not exists (select 1 from core.taxonomy_source_ref r
                      where r.entity_schema = 'core' and r.entity_table = 'character' and r.entity_id = ch.id);
  if v_n <> 0 then raise exception '#5079: % loaded characters have no source provenance', v_n; end if;

  select count(*) into v_n from core.character where metadata ->> 'issue' = v_issue and licensor_id is null;
  if v_n <> 0 then raise exception '#5079: % loaded characters have no licensor', v_n; end if;
end
$characters$;
