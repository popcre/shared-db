// #5758 Step 1 — merch-group codes only. Descriptions are not item data: the
// vendor's /items and /itemDetails snapshots intermittently omit
// merchGroupNNDesc for the same merchGroupNN code, and hashing that family
// recorded the omission as a nightly "change" for ~90% of coldlion.change_log
// (baseline docs/verification/db-anti-bloat-5758/20261105T2318Z/baseline.md:
// 2994 of 3000 sampled item_merch_group updates and 2981 of 3000 item_header
// updates changed descriptions only).
import test from "node:test";
import assert from "node:assert/strict";
import { ITEM_SPECS, MASTER_SPECS } from "./coldlion-landing/lib/master-specs.mjs";
import { projectCurrentRows, projectItemSlots, stripSlotDescFields } from "./coldlion-landing/lib/project-masters.mjs";
import { buildMasterLoadSql } from "./coldlion-landing/lib/load-masters.mjs";
import { sourceHash } from "./coldlion-landing/lib/values.mjs";

const RUN = "22222222-2222-4222-8222-222222222222";
const NOW = "2026-11-05T23:00:00.000Z";

function sourceFor(spec, overrides = {}) {
  const row = {};
  for (const field of spec.fields) {
    row[field.api] = field.type === "num" ? "1.25" : field.type === "date" ? "2026-01-02" : field.type === "ts" ? "2026-01-02T03:04:05Z" : `SYN-${field.api}`;
  }
  for (const ignored of spec.ignored ?? []) row[ignored] = null;
  if (spec.slots) for (let n = 1; n <= 14; n += 1) {
    const nn = String(n).padStart(2, "0");
    row[`merchGroup${nn}`] = n <= 2 ? `MG${nn}` : null;
    row[`merchGroup${nn}Desc`] = n <= 2 ? `Synthetic ${nn}` : null;
  }
  if (spec.fields.some((field) => field.api === "divisionCode")) row.divisionCode = "SD001";
  if (spec.fields.some((field) => field.api === "itemNo")) row.itemNo = "SYN-1";
  row.companyCode = "SYNCO";
  return { ...row, ...overrides };
}

function itemHeaderSource(overrides = {}) {
  return sourceFor(ITEM_SPECS.item_header, overrides);
}

test("slot hash ignores a description flapping between valued and blank", () => {
  const valued = projectItemSlots([itemHeaderSource()], { runId: RUN, fetchedAt: NOW });
  const blank = projectItemSlots([itemHeaderSource({ merchGroup01Desc: null, merchGroup02Desc: "" })], { runId: RUN, fetchedAt: NOW });
  assert.equal(valued.length, 2);
  assert.deepEqual(valued.map((r) => r.source_hash), blank.map((r) => r.source_hash));
  // The hash is over codes only, exactly the canonical {slotNo, mgCode} object.
  assert.equal(valued[0].source_hash, sourceHash({ slotNo: 1, mgCode: "MG01" }));
  assert.equal(valued[0].mg_desc, undefined);
});

test("a real code change still changes the slot hash", () => {
  const before = projectItemSlots([itemHeaderSource()], { runId: RUN, fetchedAt: NOW });
  const after = projectItemSlots([itemHeaderSource({ merchGroup01: "MG99" })], { runId: RUN, fetchedAt: NOW });
  assert.notEqual(before[0].source_hash, after[0].source_hash);
});

test("item_header and item_detail hashes ignore merchGroupNNDesc, keep everything else", () => {
  for (const spec of [ITEM_SPECS.item_header, ITEM_SPECS.item_detail]) {
    const base = sourceFor(spec, spec === ITEM_SPECS.item_detail ? { itemPkey: "P1" } : {});
    const flap = { ...base };
    for (let n = 1; n <= 14; n += 1) flap[`merchGroup${String(n).padStart(2, "0")}Desc`] = null;
    const a = projectCurrentRows(spec, [base], { runId: RUN, fetchedAt: NOW });
    const b = projectCurrentRows(spec, [flap], { runId: RUN, fetchedAt: NOW });
    assert.equal(a.rows[0].source_hash, b.rows[0].source_hash, `${spec.endpoint} hash must not move on a description flap`);
    const changedField = spec.fields.find((field) => !spec.key.includes(field.column) && !["ts", "date", "num"].includes(field.type));
    const realChange = projectCurrentRows(spec, [{ ...base, [changedField.api]: "SYN-changed" }], { runId: RUN, fetchedAt: NOW });
    assert.notEqual(a.rows[0].source_hash, realChange.rows[0].source_hash, `${spec.endpoint} hash must move on a real change`);
  }
});

test("stripSlotDescFields removes the merchGroupNNDesc family and nothing else", () => {
  const stripped = stripSlotDescFields(itemHeaderSource({ merchGroup1Desc: "not the two-digit pattern" }));
  for (let n = 1; n <= 14; n += 1) assert.equal(stripped[`merchGroup${String(n).padStart(2, "0")}Desc`], undefined);
  assert.equal(stripped.merchGroup1Desc, "not the two-digit pattern");
  assert.equal(stripped.merchGroup01, "MG01");
  assert.equal(stripped.itemDesc, "SYN-itemDesc");
});

test("change_log writes are suppressed for hash-only rehash and description flaps", () => {
  const headerRows = projectCurrentRows(ITEM_SPECS.item_header, [itemHeaderSource()], { runId: RUN, fetchedAt: NOW }).rows;
  const detailRows = projectCurrentRows(ITEM_SPECS.item_detail, [sourceFor(ITEM_SPECS.item_detail, { itemPkey: "P1" })], { runId: RUN, fetchedAt: NOW }).rows;
  const customerRows = projectCurrentRows(MASTER_SPECS.customer, [sourceFor(MASTER_SPECS.customer, { customerCode: "C1" })], { runId: RUN, fetchedAt: NOW }).rows;
  const sql = buildMasterLoadSql({
    loads: [
      { table: "customer", spec: MASTER_SPECS.customer, rows: customerRows, run: { id: RUN, endpoint: "/customers", companyCode: "SYNCO", requestedBy: "test", startedAt: NOW, finishedAt: NOW, durationMs: 0, rowsFetched: 1 } },
      { table: "item_header", spec: ITEM_SPECS.item_header, rows: headerRows, run: { id: RUN, endpoint: "/items", companyCode: "SYNCO", requestedBy: "test", startedAt: NOW, finishedAt: NOW, durationMs: 0, rowsFetched: 1 } },
      { table: "item_detail", spec: ITEM_SPECS.item_detail, rows: detailRows, run: { id: RUN, endpoint: "/itemDetails", companyCode: "SYNCO", requestedBy: "test", startedAt: NOW, finishedAt: NOW, durationMs: 0, rowsFetched: 1 } },
    ],
    itemSlots: projectItemSlots([itemHeaderSource()], { runId: RUN, fetchedAt: NOW }),
    affectedItemGrains: [{ company_code: "SYNCO", division_code: "SD001", item_no: "SYN-1", item_pkey: null, run_id: RUN }],
  });
  // Slot-bearing tables hash-suppress via content compare that ignores the
  // merchGroupNNDesc family on both sides of the change.
  const guardUses = sql.match(/is distinct from \(coalesce\(prior\.new_raw/g) ?? [];
  assert.equal(guardUses.length, 2, "item_header and item_detail change_log writes carry the rehash suppression");
  assert.ok(sql.includes("(s.source_raw - array['merchGroup01Desc'"));
  // The non-slot master (customer) keeps the plain hash condition.
  const customerGuard = sql.match(/where t\.company_code is null\s+or t\.source_hash <> s\.source_hash;/);
  assert.ok(customerGuard, "customer change_log keeps the hash-only condition");
  // Slot statements no longer read or write mg_desc anywhere, and the slot
  // suppression strips it from both sides so it also holds before the column
  // drop applies.
  assert.ok(!sql.includes("mg_desc=excluded.mg_desc"));
  assert.ok(!/\$\{?sqlText\(r\.mg_desc\)/.test(sql));
  const slotSuppression = sql.match(/to_jsonb\(s\)-array\['run_id','fetched_at','source_hash','mg_desc','id','first_seen_at','last_seen_at'\]/);
  assert.ok(slotSuppression, "slot change_log suppression strips bookkeeping, hash, surrogate id and mg_desc");
});
