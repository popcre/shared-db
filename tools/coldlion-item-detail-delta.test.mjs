import test from "node:test";
import assert from "node:assert/strict";

import {
  DELTA_REQUESTED_BY,
  MAX_DELTA_ITEMS,
  buildItemDetailDeltaSql,
  fetchItemDetails,
  newItemsFromPayload,
  validDetailRow,
} from "./coldlion-landing/lib/item-detail-delta.mjs";
import { landNewItemDetails, parseExistingItemIdentities } from "./sync-coldlion-items.mjs";

const payload = (itemNo, divisionCode = "CW001") => ({ companyCode: "EDGEHOME", divisionCode, itemNo, itemDesc: `desc ${itemNo}` });
const detail = (itemNo, extra = {}) => ({ companyCode: "EDGEHOME", divisionCode: "CW001", itemNo, itemPkey: "1", prePackCode: null, ...extra });

test("newness is (company, division, itemNo) — item numbers repeat across divisions", () => {
  const items = [payload("A1"), payload(" A2 "), payload("A3", "EP001"), { companyCode: "EDGEHOME", divisionCode: "CW001" }, payload("A4", "SP001")];
  const existing = [["EDGEHOME", "CW001", "A1"], ["EDGEHOME", "CW001", "A4"]];
  const fresh = newItemsFromPayload(items, existing);
  assert.deepEqual(fresh.map((row) => [row.companyCode, row.divisionCode, row.itemNo.trim()]), [["EDGEHOME", "CW001", "A2"], ["EDGEHOME", "SP001", "A4"]]);
});

test("validDetailRow rejects out-of-scope and blank-key rows; trimmed keys pass", () => {
  assert.equal(validDetailRow(detail("N1"), { companyCode: "EDGEHOME", divisionCode: "CW001", itemNo: "N1" }), null);
  assert.equal(validDetailRow(detail(" N1 ", { itemNo: " N1 " }), { companyCode: "EDGEHOME", divisionCode: "CW001", itemNo: "N1" }), null);
  assert.match(validDetailRow(detail("OTHER"), { companyCode: "EDGEHOME", divisionCode: "CW001", itemNo: "N1" }), /outside the requested scope/);
  assert.match(validDetailRow(detail("N1", { divisionCode: "EP001" }), { companyCode: "EDGEHOME", divisionCode: "CW001", itemNo: "N1" }), /outside the requested scope|EP001/);
  assert.match(validDetailRow(detail("N1", { itemPkey: " " }), { companyCode: "EDGEHOME", divisionCode: "CW001", itemNo: "N1" }), /blank natural key/);
});

test("fetchItemDetails asks itemNo-filtered, carries a timeout signal, and refuses non-array bodies", async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url: String(url), options });
    if (String(url).includes("itemNo=bad")) return { ok: true, json: async () => ({ not: "array" }) };
    return { ok: true, json: async () => [detail("N1")] };
  };
  const rows = await fetchItemDetails("k", { companyCode: "EDGEHOME", divisionCode: "SP001", itemNo: "N1" }, fetchImpl);
  assert.equal(rows.length, 1);
  assert.match(calls[0].url, /\/itemDetails\?companyCode=EDGEHOME&divisionCode=SP001&itemNo=N1$/);
  assert.equal(calls[0].options.headers["X-API-Key"], "k");
  assert.ok(calls[0].options.signal, "per-call timeout signal is required");
  await assert.rejects(fetchItemDetails("k", { companyCode: "EDGEHOME", divisionCode: "CW001", itemNo: "bad" }, fetchImpl), /non-array/);
});

const run = { id: "00000000-0000-4000-8000-000000004974", companyCode: "EDGEHOME", requestParams: { items: ["N1"] }, requestedBy: DELTA_REQUESTED_BY, startedAt: "2026-10-28T19:00:00.000Z", fetchedAt: "2026-10-28T19:00:05.000Z", notes: {} };

test("delta SQL inserts sync_run first, lands insert-only, finishes with counts and notes", () => {
  const sql = buildItemDetailDeltaSql({ run, headerRows: [payload("N1")], detailRows: [detail("N1", { prePackCode: "PPK-X" })] });
  const runInsertAt = sql.indexOf("insert into coldlion.sync_run");
  const headerInsertAt = sql.indexOf("insert into coldlion.item_header");
  const detailInsertAt = sql.indexOf("insert into coldlion.item_detail");
  assert.ok(runInsertAt >= 0 && runInsertAt < headerInsertAt && runInsertAt < detailInsertAt, "sync_run must land before its FK children");
  assert.match(sql, /on conflict \(company_code, division_code, item_no\) do nothing/);
  assert.match(sql, /on conflict \(company_code, division_code, item_no, item_pkey\) do nothing/);
  assert.ok(!sql.includes("do update"), "the delta must never update rows the nightly masters owns");
  assert.match(sql, /'running'/);
  assert.match(sql, /update coldlion\.sync_run set status = 'succeeded'/);
  // sync_run.notes is TEXT: a ::jsonb cast there fails every batch (round 2, C1).
  assert.doesNotMatch(sql, /notes\s*=\s*'[^']*'::jsonb/);
  assert.match(sql, /notes\s*=\s*'\{/);
  assert.match(sql, /insert into coldlion\.change_log[^;]*'item_header'/s);
  assert.match(sql, /insert into coldlion\.change_log[^;]*'item_detail'/s);
  assert.match(sql, /'PPK-X'/);
  assert.match(sql, /^begin;$/m);
  assert.match(sql, /^commit;$/m);
  assert.doesNotMatch(sql, /source_raw/, "the landing tables have no source_raw column");
});

test("empty detail batches still create the count table and runnable SQL", () => {
  const sql = buildItemDetailDeltaSql({ run, headerRows: [payload("N1")], detailRows: [] });
  assert.match(sql, /create temp table _delta_item_detail_inserted on commit drop as select[^;]*where false;/);
  const none = buildItemDetailDeltaSql({ run, headerRows: [], detailRows: [] });
  assert.doesNotMatch(none, /insert into coldlion\.item_header/);
  assert.doesNotMatch(none, /insert into coldlion\.item_detail/);
});

test("parseExistingItemIdentities reads (company, division, item) box rows", () => {
  const stdout = " ?column? | ?column? | btrim \n----------+----------+--------\n EDGEHOME | CW001    |  A1 \n EDGEHOME | SP001   | A4\n(2 rows)\n";
  assert.deepEqual(parseExistingItemIdentities(stdout), [["EDGEHOME", "CW001", "A1"], ["EDGEHOME", "SP001", "A4"]]);
  assert.deepEqual(parseExistingItemIdentities("no table"), []);
});

test("landNewItemDetails lands validated details; pathological feeds land nothing", async () => {
  const sqls = [];
  const runSqlImpl = (sql) => { sqls.push(sql); return " ?column? | ?column? | btrim \n----------+----------+--------\n EDGEHOME | CW001 | A1 \n(1 row)\n"; };
  const fetchImpl = async () => ({ ok: true, json: async () => [detail("N1", { prePackCode: "PPK-X" })] });
  const landed = await landNewItemDetails("k", [payload("A1"), payload("N1")], { runSqlImpl, fetchImpl });
  assert.equal(landed.newItems, 1);
  assert.equal(landed.detailsLanded, 1);
  assert.deepEqual(landed.failures, []);
  assert.equal(sqls.length, 2);
  assert.match(sqls[1], /insert into coldlion\.item_detail/);

  const none = await landNewItemDetails("k", [payload("A1")], { runSqlImpl, fetchImpl });
  assert.equal(none.newItems, 0);
  assert.equal(sqls.length, 3, "the existing-items query still runs");
  assert.ok(!sqls[2].includes("insert into coldlion.item_detail"), "no landing when nothing is new");

  const many = Array.from({ length: MAX_DELTA_ITEMS + 1 }, (_, index) => payload(`B${index}`));
  const refused = await landNewItemDetails("k", many, { runSqlImpl, fetchImpl });
  assert.equal(refused.newItems, MAX_DELTA_ITEMS + 1);
  assert.equal(refused.detailsLanded, 0);
  assert.match(refused.refused, /delta cap/);
  assert.equal(sqls.length, 4, "a pathological feed runs no per-item GETs");
  assert.ok(!sqls[3].includes("insert into coldlion.item_detail"), "a pathological feed lands nothing");
});

test("per-item failures — fetch or validation — are reported and recorded in the run notes, never fatal", async () => {
  const sqls = [];
  const runSqlImpl = (sql) => { sqls.push(sql); return " ?column? | ?column? | btrim \n----------+----------+--------\n EDGEHOME | CW001 | A1 \n(1 row)\n"; };
  const fetchImpl = async (url) => {
    if (String(url).includes("itemNo=N2")) return { ok: false, status: 500, json: async () => ({}) };
    if (String(url).includes("itemNo=N3")) return { ok: true, json: async () => [detail("SOMEONE-ELSE")] };
    return { ok: true, json: async () => [detail("N1")] };
  };
  const landed = await landNewItemDetails("k", [payload("A1"), payload("N1"), payload("N2"), payload("N3")], { runSqlImpl, fetchImpl });
  assert.equal(landed.detailsLanded, 1);
  assert.equal(landed.failures.length, 2);
  assert.ok(landed.failures.some((f) => f.itemNo === "N2" && /HTTP 500/.test(f.message)));
  assert.ok(landed.failures.some((f) => f.itemNo === "N3" && /rejected/.test(f.message)));
  assert.match(sqls[1], /perItemFailures/, "failures are DB-visible in the sync_run notes");
});
