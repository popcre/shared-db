# Licensing and property master data — one-page structure map

**Status:** current front door for the licensor / property / character / style-guide
structure. **Date:** 2026-10-22. **Author:** ZCode session (owner-requested
consolidation). Every count below was measured live, read-only, against production
`qsllyeztdwjgirsysgai` on **2026-10-22**, and is labeled with its exact table or
vocabulary — an unlabeled count in this area is meaningless by rule.

Why this page exists: the structure is documented well but scattered across ten
plus files, and sessions keep re-deriving it wrongly. This is the map. The
authority for business meaning is
[`business-rules/licensing-master-data.md`](business-rules/licensing-master-data.md);
the machine-readable authority for which source family covers which licensor is
[`config/db-data-admin-property-source-coverage.json`](../config/db-data-admin-property-source-coverage.json)
(39 families; dispositions `exposed` / `not_applicable` / `blocked`). This page
never overrides either.

## The layers (counts live 2026-10-22)

| Layer | Role | Tables | Rows |
|---|---|---|---|
| ColdLion ERP mirrors | Feed targets for official licensor names and property membership | `plm.erp_licensor` (0 — guarded licensor sync not loaded yet; today's 27 `core.licensor` names are maintained by the licensing lane), `plm.erp_property` (10) | 0 / 10 |
| Authorized portal scrapes | Own property names, ownership, entities, and **direct relationships** inside their coverage; raw, byte-for-byte, RLS'd | exposed property vocabularies (from the coverage manifest): Disney OPA Submissions `plm.opa_property` **1,524** (multi-studio, per-row `opa_property_studio_resolution`: disney 244 / marvel 205 / pixar 64 / lucasfilm 2 / unresolved 910 / ambiguous 20); Disney DCP Creative `plm.dcp_property` 237; Marvel DCP `plm.marvel_dcp_property` 18; **Marvel ASGARD** `plm.marvel_asgard_style_guide` 75; Lucasfilm DCP `plm.lucasfilm_dcp_property` 70; 20th-Century DCP `plm.twentieth_century_dcp_property` 0; **Paramount TrackerPlus Submissions** `plm.pmt_trackerplus_submission_property` 35; Paramount Creative `plm.pmt_property` 134; Warner STARLABS Creative `plm.wb_property` 525; NBCU Creative `plm.nbcu_property` 249; **WildBrain** `plm.wildbrain_era` 10; **Sega Submissions** `plm.sega_submission_property` 6; Sega DSI Creative `plm.sega_property` 440; **Coca-Cola** `plm.coke_asset_property_option` 166; **WWE** `plm.wwe_property` 1. Sesame's capture carries **no** source property vocabulary (not applicable). DCP families are Creative evidence only — they cannot assign property ownership | see left |
| Canonical masters | Stable uuid identities shared by every app | `core.licensor` 27, `core.property` 262 (NOT NULL `licensor_id`; known caveats below), `core.customer` 826, `core.factory` 93 (+ aliases + `core.company_source_ref` 830 coldlion / 54 designflow_plm / 105 directus, `core.factory_source_ref` 104 coldlion / 0 designflow) | see left |
| Relationship tables | Links become canonical **only when the authorized source publishes them** | per relationship: `*_source_edge` table + link table + `*_current` view (`property_character`, `property_style_guide`, `style_guide_character`, `property_franchise`) plus entity tables `core.character`, `core.style_guide`, `core.franchise` — **every one of these 11 objects holds 0 rows today** | 0 |
| Application mirrors | Legacy-shaped copies each app keeps until its cutover | DesignFlow: `dflow_prod."licenseList"` 19; `dflow_prod.properties_and_characters` = **500 PROPERTY + 9,622 CHARACTER appearance rows (8,370 distinct names)** — never quote 10,122 as a property count; `dflow_prod.property_character_associations` 9,622; `dflow_prod.customers` 58 | live |

`core.property` caveats (from the 2026-09-03 reconciliation): some rows are
character-level entries filed as properties (most visibly in the Warner family —
11 of 14 DC rows), and 197 of 262 rows appear in none of the four extracts then
compared. It is the master, not a clean mirror of licensor catalogues.

Merch groups are a **separate system**: ColdLion dictionaries MG01–MG14 per
division; licensors/properties can appear as *rows in the merchGroup tables* —
they are not those tables. See
[`merch-group-taxonomy-architecture.md`](merch-group-taxonomy-architecture.md) and
[`business-rules/merchandise-and-product-taxonomy.md`](business-rules/merchandise-and-product-taxonomy.md).

## The licensor → property parent link

There is **no separate link table**: the parent edge is the mandatory column
`core.property.licensor_id → core.licensor(id)` (constraint
`property_licensor_id_fkey`, `ON DELETE RESTRICT`), enforced since phase 1
(2026-07-24). Legacy DesignFlow used an integer `licensor_id` → `licenseList`
column. The old DesignFlow parent-child *tree* is not part of the copied table
(`dflow_prod.properties_and_characters` has no parent column); its last
measurement — 111 unparented of 614 properties, 51 of them active — dates from
2026-08-03 over a 2026-05-07 snapshot, and the cutover plan's Phase 3B still
owns the re-measure. Treat 111/51 as dated history, not current fact.

## Selected settled rulings (5 of roughly 15 — the full set lives in the business-rules file)

- **2026-09-14** Disney, Marvel, Lucasfilm/Star Wars are **three separate
  licensors**; minimum guarantees not cross-collateralized; never merge.
- **2026-09-06** Paramount, Viacom Multi and Nickelodeon are **one** licensor
  (`VM`).
- **2026-08-23** Warner's licensed properties are defined by the signed
  agreement + Amendments 1–3 (163 properties; confidential list only in the
  private `licensor-source-data` repo).
- **2026-09-25** WildBrain has exactly **one** POP property: Strawberry
  Shortcake Classic.
- **2026-10-11** An item's property must **exactly match the licensor's
  submission vocabulary**; ColdLion never enlarges an authorized vocabulary;
  **similar names are never a mapping**.

Also settled and easy to miss: the 2026-08-31 studio-placement and 2026-09-05
entitlement rulings (OPA), source-`licensor_id` provenance, flat sub-licensing,
talent likeness, and DCP withdrawal signals — all in the business-rules file.

## Where each mapping stands (2026-10-22)

- **Licensors:** old 19-row DesignFlow list → `core.licensor` mostly ruled
  (see rulings above; the old `Dis/Mrv/SW` combo row splits three ways).
- **Properties:** 500 old rows resolve **per licensor** through that licensor's
  authorized vocabulary (families table above), or — where the manifest says no
  source property vocabulary exists (e.g. Sesame) — through ColdLion-only rules
  (start Potential; guarded membership flips Active/Inactive). Resolution lives
  in the licensing lane with the DB Data Admin review screens — never in
  name-matching.
- **Customers:** `core.company_source_ref` already records
  `designflow_plm/customers/<id>` links for **54 of 58** old rows. ColdLion owns
  official customer names.
- **Vendors/factories:** **zero** DesignFlow refs in `core.factory_source_ref`;
  needs the reviewed one-time match (ColdLion refs exist: 104).
- **Characters:** 9,622 appearance rows / 8,370 distinct names wait on property
  resolution. The backfill plan resolves them to 6,538 canonical characters
  (8,878 appearances auto-resolved by rule, 590 excluded) but has **not
  started** — blocked on licensing round 2 and the §8a code ruling
  ([`fix_characters_style_guides.md`](../fix_characters_style_guides.md)). Old
  associations are evidence, never authority.

## Verify it yourself

```sql
select type, count(*), count(distinct name) from dflow_prod.properties_and_characters group by 1;
select source_system, count(*) from core.company_source_ref group by 1;
select count(*) from core.property;                       -- 262
select count(*) from plm.opa_property;                    -- 1,524
select studio_code, resolution_status, count(*) from plm.opa_property_studio_resolution group by 1,2;
select 'factory_ref', source_system, count(*) from core.factory_source_ref group by 2;
```

## Deeper docs

Scrape contract: [`licensor-portal-scrape-source-schema-20260807.md`](licensor-portal-scrape-source-schema-20260807.md).
First reconciliation run: [`licensor-source-reconciliation-20260903.md`](licensor-source-reconciliation-20260903.md).
Two-universes correction: [`core-properties-and-characters-what-it-actually-is.md`](core-properties-and-characters-what-it-actually-is.md).
Phase-1 parent-edge design: [`app-migration-notes/coldlion-licensor-property-phase1-20260724.md`](app-migration-notes/coldlion-licensor-property-phase1-20260724.md).
Old parent-tree design: [`licensor-property-parent-child-design-20260802.md`](licensor-property-parent-child-design-20260802.md).
Whole-project schema map: [`unified-supabase-schema-map.md`](unified-supabase-schema-map.md).
