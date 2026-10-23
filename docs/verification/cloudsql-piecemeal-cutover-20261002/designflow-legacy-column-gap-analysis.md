# DesignFlow legacy column gap analysis (2026-10-23)

Purpose: before DesignFlow moves from the legacy CloudSQL-shaped tables to the
normalized canonical tables, every column the application code uses must have
a home. This records what was found. Companion to
`designflow-code-table-usage.md` (table level); this file is column level.

Evidence basis: generated `types/database.types.ts` at `dd8fb725a` and model /
service code in the five DesignFlow repositories (`designflow-backend`,
`-item-master`, `-tracking`, `-data-syncing`, `-frontend`), main checkouts only.
The live database was NOT queried (Supabase connection was down); recheck live
before any migration.

Note: legacy-shaped copies (`core."licenseList"`, `RFQItem`, `itemHeader`,
`ProdOrderHeader`, `customers`, `Factory`) still exist, and
`backend/config/table-schema-map.js` points non-production at them. Gaps below
are against the normalized targets.

## Owner rulings (Albert, 2026-10-23)

- Every field the application code uses must be present in the new schema.
- The application code decides which merch group slots get real columns.
- Item merch group slots 12–14 do NOT get columns (only the sync writes them).

## Licensor / license

`core.licensor` has only `code`, `name`, `status`, `metadata`, timestamps. No
royalty columns. Royalty terms live on legacy `licenseList` (per license, not
per licensor): `licenseList_royalty_rate`, `licenseList_fob_royalty_rate`, plus
`licenseList_auditlog`. Used by `designflow-backend/models/lib.model.js`
(~260–310). Needs a license-agreement table linked to licensor (see
`docs/normalized-licensing-master-dependency-audit-20260813.md`).
Also: no approved old-to-new ID mapping for `properties_and_characters` /
`property_character_associations` into `core.property` / `core.character` /
`core.style_guide`.

## Items (`itemHeader`, all services) → `plm.item`

`plm.item` has one `merch_group_id`. Missing: dimensions and weights
(`item_length/width/depth/weight_size`, `carton_*`, `item_cbm_size`), `uom_*`,
`hts_num_ext_fk`, `hts2_num_ext_fk`, prices (`retail_price`, `selling_price`,
`udf_item_priceA`–`H`, `compare_price`, `costcomp*`), `season_code_fk`,
`origin_country_fk`, `mfg_lead_time`, `innerpack_qty`, `vendor_code_fk`,
`old_item_num`, all `udf_freeform_*`, `udf_date*`, `udf_int*`, `udf_num*`,
`udf_yesno*`. `art_piece` (item-master) has nine merch group references with no
canonical foreign key.

### Merch group slots on the item

The merch group list itself is loaded from the API into `core.merch_group`.
`item_import` (landing) has `merch_group_01`–`06` plus a `merch_groups` JSON.
Use of `udf_merchgroupNN` in services/helpers/screens (models and tests excluded):

| Slots | Use | Column needed |
|---|---|---|
| 01–11, 15 | read by backend autofill, item-master library/numbering, tracking, frontend item detail | yes |
| 12–14 | only written by data-syncing from the source system | no (ruling) |
| 16–25 | data-syncing only sets them to null | no |

## Merch groups → `core.merch_group`

Missing: `ItemNoCode`, `mgTypeCode`, `mgCode2`, `mgCategory`, company and
division keys, `createdUser`, `modUser`.

## Vendors / factories

`core.vendor` mirrors legacy 1:1 (includes `vendor_passw`, needs security
review). `core.factory` missing `factory_nickname`, `factory_access`,
`sort_order`.

## Customers → `core.customer`

Missing: `customers_level`, `_dilution`, `_logistic_load`, `_subscription`,
`_subleveladmin`, `_notificationsms`, `_notificationemail`, `_expire`,
`_passw`, `_logo`, `_auditlog`.

## RFQ → `plm.rfq_item`

`plm.rfq_item` has only item, group, status, target cost. `RFQItem` is missing
~100 columns: gen/lic pricing across fob/whse/poe/mddp (sale, sell, royalty,
net sell, margin, entered values), `fob_cost`, `landed_cost`, `duty_rate*`,
`freight`, `cbm*`, `case_pack`, `quantity`, `dilution`, `comp_retail`,
`wholesale`, `license`, `royalty`, `step`, `choosen_vendor`, `agent`,
`udf1`–`4`, `picture`, `tech_pack_link`. `RFQVendor` missing `amount`,
`cbm_pc`, `carton_*`, `lead_time`, `price_terms`, `fob_country`, `fob_port`,
`quote_date`, `requote_requested`, `std_vendor_id_fk`, archive flags.
`UDFTable` drives part of the RFQ grid joins and must move with it.

## Production orders → `plm.production_order`

Header missing hang-tag, safety-test, photo, inspection and doc tracking flags,
deposit/payment columns, `vendorProc`/`agentProc`/`forwarderProc`,
`currencyCode`, `payTermCode`, `prod_cost`, `cbm`, `svn`, `mg5`. Detail missing
`colorCode`, `sizeCode`, `wipQty`, `CancelledQty`, `MovedQty`, `*Fkey`,
`CostSheetFkey`, `BOMFKey`, `merchGroup05Desc`.

## No normalized replacement yet

Samples, UDF/grid definitions, users and roles, HTS lookup.

## Scale

About 65 legacy columns map today, out of roughly 450 that the code uses.

## Next steps

1. Turn this into a column-by-column crosswalk, checked against real queries
   (not only model files) and against the live schema.
2. Open one issue per business area and claim the objects (`shared-db-change`).
   Start with license agreements, then items.
3. Regenerate the types and re-run the crosswalk until it shows zero gaps.
