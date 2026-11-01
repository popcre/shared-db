-- derived-from: none
-- Issue popcre/shared-db#5079 (claim #5313): Property/Character links published directly
-- by the licensor scrapes, for every core.property reachable by an exact key chain.
--
-- Owner statement, Albert Hazan, 2026-11-01 (verbatim): "our property list (in coldlion)
-- was copied directly from our licensor website scrapes".
--
-- NO LICENSED VALUES ARE IN THIS FILE. Every name is read inside the database.
--
-- CHAIN. core.property.code = ColdLion MG06 mg_code (only codes with one distinct
-- description) -> that description EXACTLY equals the scrape Property name (case and
-- spelling included; only surrounding space is trimmed) -> the scrape's own Property/
-- Character edge -> the core.character loaded from that scrape identity by migration
-- 20261030034959. This is a copy's exact name, not the similar-name mapping refused by
-- the 2026-10-11 ruling. Every source edge used is a direct publication by the portal.
--
-- LICENSOR. Property and Character must already share a licensor. Warner-scrape characters
-- all belong to WB, so DC and HP Properties produce no link here; that is a licensor
-- ownership question this load does not decide. OPA Properties must also carry canonical
-- studio evidence naming the Property's licensor.
--
-- Insert-only and idempotent: nothing existing is changed.

do $links$
declare
  v_issue constant text := 'popcre/shared-db#5079';
  v_claim constant text := 'popcre/shared-db#5313';
  v_actor constant text := 'shared-db migration 20261101122911';
  v_n integer;
begin
  create temporary table pg_temp.scrape_links on commit drop as
  with mg as (
    select mg_code, min(btrim(mg_desc)) as d
      from coldlion.merch_group_detail where mg_type_code = '06'
     group by mg_code having count(distinct btrim(mg_desc)) = 1),
  p as (
    select p.id, p.licensor_id, l.code as lic, mg.d
      from core.property p
      join core.licensor l on l.id = p.licensor_id
      join mg on mg.mg_code = p.code)
  select p.id as property_id, ch.id as character_id, p.licensor_id, 'disney_opa'::text as source_system,
         pc.licensed_property_id::text || ':' || pc.character_id::text as source_id,
         'plm.opa_property_character'::text as source_evidence
    from p
    join plm.opa_property op on btrim(op.property_name) = p.d
    join plm.opa_property_studio_resolution r
      on r.licensed_property_id = op.licensed_property_id and r.resolution_status = 'canonical'
     and p.lic = case when r.studio_code in ('disney', 'pixar') then 'DY'
                      when r.studio_code = 'marvel' then 'MV'
                      when r.studio_code = 'lucasfilm' then 'SW' end
    join plm.opa_property_character pc on pc.licensed_property_id = op.licensed_property_id
    join core.character ch on ch.code = 'disney_opa:' || pc.character_id::text and ch.licensor_id = p.licensor_id
  union
  select p.id, ch.id, p.licensor_id, 'warner_starlabs',
         w.property_id::text || ':' || w.character_id::text, 'plm.wb_property_character_normalized'
    from p
    join plm.wb_property_character_normalized w on btrim(w.property_label) = p.d
    join plm.wb_character_normalized c on c.id = w.character_id
    join core.character ch
      on ch.code = 'warner_starlabs:' || c.source_namespace || ':' || coalesce(c.source_id, c.fallback_key)
     and ch.licensor_id = p.licensor_id
  union
  select p.id, ch.id, p.licensor_id, 'nbcu_creative_asset_factory',
         n.property_key || ':' || n.character_key, 'plm.nbcu_property_character'
    from p
    join plm.nbcu_property_character n on btrim(n.property_label) = p.d
    join core.character ch on ch.code = 'nbcu_creative_asset_factory:' || n.character_key and ch.licensor_id = p.licensor_id
  union
  select p.id, ch.id, p.licensor_id, 'paramount_creative_library',
         pp.property_source_id::text || ':' || pc.character_source_id::text, 'plm.pmt_property_character'
    from p
    join (select distinct property_source_id, btrim(property_name) as n from plm.pmt_property) pp on pp.n = p.d
    join plm.pmt_property_character pc on pc.property_source_id = pp.property_source_id
    join core.character ch on ch.code = 'paramount_creative_library:' || pc.character_source_id::text and ch.licensor_id = p.licensor_id;

  insert into core.property_character_source_edge
    (property_id, character_id, licensor_id, source_system, source_id, source_evidence, evidence_kind,
     observation_count, confidence, is_current, metadata, created_by, updated_by)
  select distinct on (l.property_id, l.character_id, l.source_system)
         l.property_id, l.character_id, l.licensor_id, l.source_system, l.source_id, l.source_evidence,
         'direct_source_assertion', 0, null, true,
         jsonb_build_object('loaded_by', v_actor, 'issue', v_issue, 'claim', v_claim), v_actor, v_actor
    from pg_temp.scrape_links l
   where not exists (select 1 from core.property_character_source_edge e
                      where e.property_id = l.property_id and e.character_id = l.character_id
                        and e.licensor_id = l.licensor_id and e.source_system = l.source_system
                        and e.evidence_kind = 'direct_source_assertion' and e.is_current)
   order by l.property_id, l.character_id, l.source_system, l.source_id;

  insert into core.property_character_associations (property_id, character_id, is_current)
  select distinct l.property_id, l.character_id, true from pg_temp.scrape_links l
  on conflict (property_id, character_id) do nothing;

  -- Self-check: every chain pair is now a current association.
  select count(*) into v_n from (select distinct property_id, character_id from pg_temp.scrape_links) l
   where not exists (select 1 from core.property_character_associations a
                      where a.property_id = l.property_id and a.character_id = l.character_id and a.is_current);
  if v_n <> 0 then raise exception '#5079 links: % chain pairs have no current association', v_n; end if;
end
$links$;
