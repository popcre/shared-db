# DesignFlow legacy → canonical crosswalk (2026-10-23)

Follows `designflow-legacy-column-gap-analysis.md` (steps 1 and 2 of its
"Next steps"). The column rows are in `designflow-legacy-column-crosswalk.csv`
(923 legacy columns, 21 tables). This file holds the table-level verdict,
the recorded decision, and how the CSV was built.

## 1. Design rules the new schema must keep

Taken from `docs/core-master-data-consolidation-aim.md` §§4, 7, 10, 11,
`docs/architecture.md`, and the shape of the existing canonical tables.

1. One canonical home per shared entity. No second copy of licensor,
   property, customer, vendor/factory, merch group, profile.
2. DesignFlow is not an authority for licensing master data. Its values may be
   kept only as labelled source references.
3. Shared things are referenced by key (uuid FK to `core.*` / `app.profile`),
   never by a copied code or name string.
4. Every migrated row keeps `source_system` + `source_id`.
5. Repeating groups (numbered slots, arrays, flag/date pairs, pricing grids)
   become child rows, not wide numbered columns.
6. snake_case names; no passwords outside Supabase Auth.
7. Tables that only DesignFlow uses and that hold no shared truth may stay
   application-owned.

## 2. Table-level verdict

**Move as-is** (application-owned, no shared truth; only change is that
references to users, items, vendors become canonical keys, and names go
snake_case where the table is recreated):

- Screen layouts: `GridLayout`, `GridChildrenLayout`, `GridChildrenLayoutOrder`,
  `GridAccessLevel`, `GridViewState`, `grid_cell_notes`.
- Custom grid definitions: `UDFTable`, `UDFComponent`, `UDFElement`,
  `UDFElementType`, `UDFGroup`, `UDFQuery`.
- Element-level access: `UIElements`, `RolePermissions` (role keys point at
  `app.role`).
- App support: `app_settings`, `ai_cache_events`, `email_logs`, `auth_token`,
  `quote_auth_token`, `AdditionalUserEmail`.
- Standardized products (eight `Standardized*` tables): DesignFlow-only
  quoting templates.
- Lead-time tables `LicensingTime`, `DesignTeamTime`, `FactoryTime`;
  `LicenseFeedBacks` catalog; `RFQStep` (new `plm.rfq_step`);
  `RFQContainer`, `RFQWhse`, `RFQItemStatus`.
- Sample cluster (seven tables): moves together as one block, as already
  decided (Decision 5, `docs/designflow-cloudsql-to-supabase-plan.md`).

**Must be reshaped** (would break rules 1–6 if copied):

- `licenseList` → per-licensor `plm.license_agreement` (new) holding the two
  royalty rates; licensor name/status stay ColdLion-owned in `core.licensor`.
- `itemHeader` → `plm.item` plus four child tables: `item_merch_group`
  (slots 01–11, 15), `item_custom_value` (numbered free-form/date/int slots),
  `item_price` (price levels A–H), and licensing milestone rows in the
  existing `plm.licensing_status` (27 `lic_*` flag/date columns). Lookup codes
  (season, division, HTS, royalty, salesperson, vendor, units) become FKs.
- `RFQItem` → `plm.rfq_item` plus `plm.rfq_item_price` (new): the 69
  gen/lic × fob/whse/poe/mddp/ldp pricing columns become rows.
- `ProdOrderHeader` → `plm.production_order` columns, with the eight `doc_*`
  flags as `plm.production_order_document` rows.
- `licensingStatus` / `licensingFeedbackReply` → existing tables plus
  assignee, mention and attachment join tables (arrays and JSON lists become
  rows; attachments go through `app.file_object`).
- `customers`, `users`, `vendor`: passwords are never moved (sign-in is
  Supabase Auth). `vendor_passw` also needs a rotation review.
- `AuditLog` old/new value and element id go into `app.activity.payload`.
- Lookup lists (season, division, company, FOB country, delivery location,
  item type): one `core` lookup each, or `plm.reference_value` if that is
  confirmed as the generic home. Codes on items point at them.
- `properties_and_characters` / `property_character_associations`: no copy;
  they need an approved old-to-new ID map into `core.property` /
  `core.character` / `core.style_guide` (rule 2).

**Not moved:** model-only tables listed in the gap analysis
(`ShippingPort`, `ProdShipmentTransitTime`, `ProdPaymentTerms`,
`RFQItemDivision`, `productions`, `licensingMilestone`, legacy `comments`) and
`itemDetail` columns (see §4).

## 3. Decision recorded (Albert, 2026-10-23)

Albert's rulings of 2026-10-23 are that every field the application code uses
must be present, the code decides, and of the ColdLion sync-only fields only
movie art, character likeness and the MG02 item-number code are kept.
Recorded consequence: **the new schema carries every area in §2 that has a
column the application reads** — licensing agreements, items, merch groups,
customers, factories/vendors, RFQ, production orders, licensing workflow,
attachments, art pieces, users, audit, comments, lookups, screen layouts,
custom grids, standardized products, lead times and samples. Areas in §2
"Move as-is" are carried as application-owned tables; areas in "Must be
reshaped" are carried in the canonical shape. Nothing the app reads stays
behind only as a legacy copy.

Assumption: "must be present" was read as "must have a home in the new
schema", not "may remain in the legacy-shaped copies". If Albert wants some
area left as a legacy copy for now, only that area's rows in the CSV change.

## 4. Crosswalk results

| Disposition | Columns |
|---|---|
| covered (existing canonical column) | 131 |
| add (new column on the canonical table) | 261 |
| reshape (child table / row form / payload) | 148 |
| not needed | 380 |
| do not move (passwords) | 3 |

Corrections to the gap analysis found while building it:

- `udf_num01` has no application reference (sync only); the read field is
  `udfnum01`. `udf_num01` is marked not needed.
- `itemDetail`: confirmed no column read. Name matches outside the sync are
  item-header fields of the same name or UI text. All 168 columns not needed.
- `core.vendor` matches legacy `vendor` column for column; all covered
  except the password.

New tables the crosswalk proposes: `plm.license_agreement`,
`plm.item_merch_group`, `plm.item_custom_value`, `plm.item_price`,
`plm.rfq_item_price`, `plm.rfq_step`, `plm.production_order_document`,
`plm.licensing_status_assignee`, `plm.licensing_feedback_mention`,
`plm.licensing_attachment`.

## 5. Method and limits

- Legacy and target columns: `types/database.types.ts` at `dd8fb725a`
  (matches live per the gap analysis).
- Reference counts: whole-word matches in DesignFlow code at
  `~/repos/dflow_plm` (backend `a6e8c16a3`, item-master `c140f308`,
  tracking `e3f3c3a0`, bff `129dae8e`, frontend `1860b258` `src/`),
  excluding Sequelize definition files, tests, nested worktrees and
  `node_modules`; query-logic files under `models/` (`lib.model*.js`,
  `db.js`) are included. Sync counts: `designflow-data-syncing`.
- `app_refs` for generic names (`id`, `status`, `name`, `comment`, `date`,
  `from`, `package`, `tags`, `cbm`, `svn`, `mg5`, …) are unreliable and are
  flagged in the note column; their disposition follows the gap analysis.
- Proposed target names are a starting point for the per-area structural
  issues (gap analysis step 3); each issue confirms them against the code
  path before claiming objects.
