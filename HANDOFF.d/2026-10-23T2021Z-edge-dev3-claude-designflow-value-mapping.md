---
issue: 4248
status: OPEN
owner: claude/licensor-royalty-rates-columns-53a904
---

# DesignFlow legacy → canonical schema: crosswalk and value-mapping rulings (2026-10-23)

Branch (pushed, not merged, no PR yet):
https://github.com/popcre/shared-db/tree/claude/licensor-royalty-rates-columns-53a904

Base URL for files below: `https://github.com/popcre/shared-db/blob/claude/licensor-royalty-rates-columns-53a904/`

- Gap analysis (input): `docs/verification/cloudsql-piecemeal-cutover-20261002/designflow-legacy-column-gap-analysis.md`
- Crosswalk narrative (this session): `docs/verification/cloudsql-piecemeal-cutover-20261002/designflow-legacy-column-crosswalk.md`
- Crosswalk rows, 923 legacy columns (this session): `docs/verification/cloudsql-piecemeal-cutover-20261002/designflow-legacy-column-crosswalk.csv`
- Official migration plan, where every owner ruling is recorded: `docs/designflow-cloudsql-to-supabase-plan.md`, section "Value-mapping decisions (owner rulings)" at the end of the file.

## 0. Business decisions only the owner can make

Put all open items below to Albert in ONE message before starting.

**Blocking:**

1. **Factory review spreadsheet.** Albert asked for it and is filling it in. It covers 176 DesignFlow factories. For each one it asks: the ColdLion code, trade name, nickname, rep names, and whether to keep it. It blocks loading factories, which blocks factory links on samples, RFQs and vendor logins. Recommendation: wait for his file, don't guess. The file is a private, gitignored local file (`.private/factory-review.csv` in the worktree). It is not on GitHub because it contains supplier names. If it is lost, regenerate it with the query in §5.4.

**A wrong guess is recoverable:**

2. Review list of **38 item-size codes** that don't match `core.product_size` (§5.3). Recommendation: send them to him in a list with sample items.
3. **Lookup "home" for season/division/company/FOB/delivery lists.** This is technical, not for Albert. Decide during the per-area issue.

**Already settled — do NOT re-ask (all 2026-10-23, Albert):**

- Every field the DesignFlow code uses must have a home in the new schema; the code decides.
- Merch group slots 12–14 get no column (only the sync writes them). Slots 16–25 are only set to null, so they get no column either.
- Of the 19 ColdLion sync-only fields, keep only movie art (`udf_yesno01`), character likeness (`udf_yesno03`) and the MG02 item-number code (`ItemNoCode`).
- Where Supabase production already has a table for the same data, use that design. Extend it if structure is missing; otherwise only map values.
- ColdLion-sourced data uses the new Supabase tables.
- License codes: `NU` → NBC (`NB`); `NK` → Viacom Multi (`VM`); `GC`/`MP` in the license list → DTR - No License (`ZZ`).
- Disney, Marvel and Star Wars are three separate licensors regardless of ownership. `DS` has 0 items and is retired.
- Licensed and non-licensed divisions have different MG05/MG06 codes and meanings. Mapping is per division, never mixed across divisions.
- ColdLion division codes are right: SP001 = Spruce Licensed, EH001 = Spruce non-Licensed, CW001 = POP. DesignFlow's division table has SP001 and EH001 swapped.
- EP001 is a different company. It is not migrated (451 items).
- Inactive licensors: Roaring Brook, Frida Kahlo, ZAG, Friends TV, Marilyn Monroe.
- Non-inventory items (per ColdLion's flag) are not imported (50 items).
- `117T3MV` and `17P1GF1` are not imported.
- Factory model: one `core.factory` from ColdLion with the legal name, plus trade name, nickname (shown everywhere), one or more rep names, and one or more vendor logins. DesignFlow-only factories (not yet bought from) are allowed.

## 1. What this application is

POP Creations (Albert's company) makes licensed and unlicensed wall decor and home goods. Divisions: POP (CW001), Spruce Licensed (SP001), Spruce non-Licensed (EH001).

DesignFlow is POP's product-lifecycle app: items, RFQs (quote requests), production orders, licensing approvals, samples and factory portals. It runs as four Cloud Run services (backend, item-master, tracking, data-syncing) plus an Angular frontend in the `popcre/designflow-*` repos. It was built on a Cloud SQL database whose data is now copied 1:1 into Supabase schema `dflow_prod`.

ColdLion is the ERP. It is the authority for items, licensors, divisions, vendors (factories) and merch groups.

`popcre/shared-db` (this repo) owns the shape of the one shared Supabase database (production project `qsllyeztdwjgirsysgai`) that all POP apps use. The goal of parent issue #4248 is to move DesignFlow off the legacy-shaped tables onto the normalized canonical tables (`core.*`, `plm.*`, `app.*`).

## 2. What we set out to do this session

Albert asked us to:

- Decide, per DesignFlow table, whether it can move unchanged or must be reshaped to respect the canonical design.
- Record which areas the new schema must carry.
- Build the column-by-column crosswalk.
- Measure how many legacy values map automatically to the new ColdLion-loaded tables.
- Take his rulings on the values that don't map, and record every ruling in the official migration plan.

## 3. Current state

**Done, committed and pushed on the branch.** Commits from `5e3bf5ebb` through the latest `bdf0ccf5b`, plus this handoff.

- Crosswalk `.md` §1–§7: design rules, as-is vs reshape verdict, the decision, counts, method, the no-home fit check, and live auto-map rates.
- Crosswalk `.csv`: 923 rows — covered 131, add 261, reshape 148, not needed 380, do not move 3 (passwords).
- Migration plan: every ruling in §0, dated.

**Not done:**

- No PR for the branch. Class `prose`; documents only.
- No schema change, no data loaded.
- Factory review is waiting on Albert.
- Size review list not yet sent.
- Proposed new tables are not claimed or created: `plm.license_agreement`, `plm.item_merch_group`, `plm.item_custom_value`, `plm.item_price`, `plm.rfq_item_price`, `plm.rfq_step`, `plm.production_order_document`, `plm.licensing_status_assignee`, `plm.licensing_feedback_mention`, `plm.licensing_attachment`, factory rep and vendor-login link tables.

## 4. What did NOT work / traps

- **Matching legacy factories by name:** only 34 of 181 match. The reason: ColdLion uses legal names, while DesignFlow uses trade names or rep names, often swapped between the name and nickname fields. Don't retry fuzzy matching. Use Albert's spreadsheet.
- **Matching sizes through DesignFlow's `itemSize` list:** 16%. It uses metric labels. Match the item's MG04 code to `core.product_size.code` instead, which gives 95%.
- **Matching production orders by number:** 0%. `plm.production_order` holds a different source (`D0555`-style numbers and `COLDLION-SO-…` sales orders). ColdLion production orders were never loaded.
- **`core.merch_group` is empty.** The loaded list is in the legacy-shaped `core."merchGroup"` (3,645 rows). Matching on code + type code gives 96%.
- **`GC` means two things.** It is "Generic" in the license list but "Global Culture" (an EH001 theme) on items. The `ZZ` ruling applies only to the license-list entry.
- **I first treated MG05 as "licensor" across all divisions.** That was wrong. In EH001, MG05 is a theme. Always filter by ColdLion division (`plm.item.raw->>'divisionCode'`).
- **DesignFlow's own division (`itemHeader.div_code_fk`) and `non_inv_item` flag disagree with ColdLion** for about 3,700 items. Never use them.
- **Wide multi-table counting queries hit the statement timeout.** Use `left join` to a distinct subquery, one table per query.
- **The `pg_trgm` `similarity()` function is not reachable** on the default search path.
- Albert first said SP001 is non-licensed. The data showed the reverse, and he confirmed ColdLion is right. If something contradicts him, show the data and ask.

## 5. Key findings

1. Live auto-map rates on the imported scope (CW001/EH001/SP001 inventory items, 18,048 items): items 98.5% by item number, merch groups 96%, depths 100%, customers 57 of 58, licensors 12 of 19 before rulings, sizes 95% by item MG04, production-order vendor codes 94% to `core.factory`.
2. `core.vendor` mirrors legacy `vendor` column for column. Only its password needs a security review.
3. Item size codes: 38 distinct codes don't match. Find them by joining item MG04 against `core.product_size`, excluding EP001 and non-inventory items.
4. Factory review file query: `dflow_prod."Factory"` (minus test rows) best-matched to `core.factory` by shared distinctive name tokens. I then hand-corrected about 20 suggestions (wrong ones cleared, `Jonhson Plastic` → `CNTNG`, `JamesAnswell` → `CNASW`, `Tongfeng Guangxing` → `CNXYZ`).
5. Item reference counts in the CSV come from whole-word matches over the DesignFlow code (method in crosswalk §5). Generic names are flagged as unreliable.

## 6. Exact next steps

1. When Albert returns the factory file, record his choices in the migration plan, without supplier rows in the public repo. You'll know it worked when every row has a code or "not in ColdLion" and a keep flag.
2. Send Albert the list of 38 unmatched size codes. You'll know it worked when each has a ruling in the plan.
3. Open one shared-db structural issue per business area under #4248, loading `shared-db-change` first. Order: license agreements → `core.merch_group` load → items (with child tables) → factories → RFQ → production orders (needs the ColdLion production-order load first). You'll know it worked when each issue claims exact objects.
4. Open a PR for this branch (docs only) and merge it per the repo rules. You'll know it worked when the crosswalk and plan are on `main`.

After finishing each step above, re-read every later step (through step 4) and the crosswalk §2/§6, and write down any drift (renamed tables, changed rulings, new blockers) in your own handoff file before continuing.

## 7. Constraints

- Shared-db structural work is claim-first. It needs a reviewer APPROVE at the exact head (observation-week rules apply).
- Production is read-only except through the migration workflow.
- Licensed row data never goes into this public repo.
- Never hand-edit `types/database.types.ts`.
- Times are given in EST/EDT.

## 8. Access

- The Supabase MCP (`mcp__supabase__execute_sql`) is connected to production `qsllyeztdwjgirsysgai`. Used read-only.
- The DesignFlow code is checked out locally under the `dflow_plm` repos folder on machine `edge-dev3`.
- No secrets were used.

## 9. Risks

- Proposed table and column names in the CSV are drafts. Confirm each against the code path in its area issue.
- If the ColdLion production-order load is never built, DesignFlow production-order history has no canonical home.
- The DesignFlow division and non-inventory flags are wrong for many items. Anything else derived from DesignFlow division is suspect.

Written 4:21 PM EDT, 2026-10-23.
