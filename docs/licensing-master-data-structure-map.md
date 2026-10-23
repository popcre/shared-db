# Licensing and property master data — one-page structure map

**Status:** current front door for the licensor / property / character / style-guide
structure. **Date:** 2026-10-22. **Author:** ZCode session (owner-requested
consolidation; every count below was measured live, read-only, against production
`qsllyeztdwjgirsysgai` on 2026-10-22).

Why this page exists: the structure is documented well but scattered across ten
plus files (business rules, scrape contracts, reconciliation reports, migration
notes), and sessions keep re-deriving it wrongly. This is the map. The authority
for business meaning is
[`business-rules/licensing-master-data.md`](business-rules/licensing-master-data.md);
this page never overrides it.

## The layers (all counts live 2026-10-22)

| Layer | Role | Tables | Rows |
|---|---|---|---|
| ColdLion ERP mirrors | Official **licensor names**; property membership active/inactive; customers; vendors | `plm.erp_licensor`, `plm.erp_property` | 0 / 10 (feed partial) |
| Authorized portal scrapes | Own **property names, ownership, entities, direct relationships** inside their coverage; raw, byte-for-byte, RLS'd | Disney OPA `plm.opa_*` (multi-studio: per-row `opa_property_studio_resolution`), Disney DCP Vault `plm.dcp_*` (**creative evidence only — cannot assign property ownership**), Warner STARLABS `plm.wb_*`, Paramount `plm.pmt_*`, NBCU `plm.nbcu_*`, Sega `plm.sega_*` | properties: 1,524 / — / 525 / 134 / 249 / 440 |
| Canonical masters | Stable uuid identities shared by every app | `core.licensor`, `core.property` (NOT NULL `licensor_id`), `core.customer`, `core.factory` (+ aliases, + `core.company_source_ref`, `core.factory_source_ref`) | 27 / 262 / 826 / — |
| Relationship tables | Links become canonical **only when the authorized source publishes them** | per relationship: `*_source_edge` table + link table + `*_current` view (`property_character`, `property_style_guide`, `style_guide_character`, `property_franchise`) + `core.character`, `core.style_guide`, `core.franchise` | **all 0** |
| Application mirrors | Legacy-shaped copies each app keeps until its cutover | DesignFlow: `dflow_prod."licenseList"` (19), `dflow_prod.properties_and_characters` (**500 PROPERTY + 9,622 CHARACTER in one table** — never quote 10,122 as a property count), `dflow_prod.property_character_associations` (9,622), `dflow_prod.customers` (58) | live |

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
column, plus a DesignFlow-owned parent-child tree *inside* the property list
(111 unparented properties; curation home still open —
[`licensor-property-parent-child-design-20260802.md`](licensor-property-parent-child-design-20260802.md)).

## Settled rulings that override intuition (all in the business-rules file)

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

## Where each mapping stands (2026-10-22)

- **Licensors:** old 19-row DesignFlow list → `core.licensor` mostly ruled
  (see rulings above; the old `Dis/Mrv/SW` combo row splits three ways).
- **Properties:** 500 old rows resolve **per licensor** through that licensor's
  authorized vocabulary, or (no-scratch licensors) through ColdLion-only rules
  (start Potential; guarded membership flips Active/Inactive). Resolution lives
  in the licensing lane with the DB Data Admin review screens — not in
  name-matching.
- **Customers:** `core.company_source_ref` already records
  `designflow_plm/customers/<id>` links for **54 of 58** old rows. ColdLion owns
  official customer names.
- **Vendors/factories:** **zero** DesignFlow refs recorded; needs the reviewed
  one-time match (ColdLion refs exist: 104).
- **Characters:** all 9,622 wait on property resolution; old associations are
  evidence, never authority.

## Verify it yourself

```sql
select type, count(*) from dflow_prod.properties_and_characters group by 1;
select source_system, count(*) from core.company_source_ref group by 1;
select count(*) from core.property;  -- 262
```

## Deeper docs

Scrape contract: [`licensor-portal-scrape-source-schema-20260807.md`](licensor-portal-scrape-source-schema-20260807.md).
First reconciliation run: [`licensor-source-reconciliation-20260903.md`](licensor-source-reconciliation-20260903.md).
Two-universes correction: [`core-properties-and-characters-what-it-actually-is.md`](core-properties-and-characters-what-it-actually-is.md).
Phase-1 parent-edge design: [`app-migration-notes/coldlion-licensor-property-phase1-20260724.md`](app-migration-notes/coldlion-licensor-property-phase1-20260724.md).
Whole-project schema map: [`unified-supabase-schema-map.md`](unified-supabase-schema-map.md).
