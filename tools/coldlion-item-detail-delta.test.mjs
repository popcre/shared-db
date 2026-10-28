import test from "node:test";
import assert from "node:assert/strict";

import {
  DELTA_REQUESTED_BY,
  MAX_DELTA_ITEMS,
  buildItemDetailDeltaSql,
  fetchItemDetails,
  newItemsFromPayload,
} from "./coldlion-landing/lib/item-detail-delta.mjs";
import { landNewItemDetails, parseExistingItemNumbers } from "./sync-coldlion-items.mjs";

const payload = (itemNo, divisionCode = "CW001") => ({ companyCode: "EDGEHOME", divisionCode, itemNo, itemDesc: `desc ${itemNo}` });

test("newItemsFromPayload keeps only genuinely new non-EP001 items", () => {
  const items = [payload("A1"), payload(" A2 "), payload("A3", "EP001"), { companyCode: "EDGEHOME", divisionCode: "CW001" }, payload("A4")];
  const fresh = newItemsFromPayload(items, ["A1", "A9"]);
  assert.deepEqual(fresh.map((row) => row.itemNo), [" A2 ", "A4"]);
});

test("fetchItemDetails asks itemNo-filtered and refuses non-array bodies", async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url: String(url), options });
    if (String(url).includes("itemNo=bad")) return { ok: true, json: async () => ({ not: "array" }) };
    return { ok: true, json: async () => [{ itemPkey: "1", prePackCode: null }] };
  };
  const rows = await fetchItemDetails("k", { companyCode: "EDGEHOME", divisionCode: "SP001", itemNo: "N1" }, fetchImpl);
  assert.equal(rows.length, 1);
  assert.match(calls[0].url, /\/itemDetails\?companyCode=EDGEHOME&divisionCode=SP001&itemNo=N1$/);
  assert.equal(calls[0].options.headers["X-API-Key"], "k");
  await assert.rejects(fetchItemDetails("k", { companyCode: "EDGEHOME", divisionCode: "CW001", itemNo: "bad" }, fetchImpl), /non-array/);
});

const run = { id: "00000000-0000-4000-8000-000000004974", companyCode: "EDGEHOME", requestParams: { items: ["N1"] }, requestedBy: DELTA_REQUESTED_BY, fetchedAt: "2026-10-28T19:00:00.000Z" };

test("buildItemDetailDeltaSql is insert-only, keys on the table PKs, and carries run bookkeeping", () => {
  const sql = buildItemDetailDeltaSql({
    run,
    headerRows: [payload("N1")],
    detailRows: [{ companyCode: "EDGEHOME", divisionCode: "CW001", itemNo: "N1", itemPkey: "1", prePackCode: "PPK-X" }],
  });
  assert.match(sql, /insert into coldlion\.item_header \([^)]*run_id[^)]*\)/);
  assert.match(sql, /insert into coldlion\.item_detail \([^)]*run_id[^)]*\)/);
  assert.match(sql, /on conflict \(company_code, division_code, item_no\) do nothing/);
  assert.match(sql, /on conflict \(company_code, division_code, item_no, item_pkey\) do nothing/);
  assert.ok(!sql.includes("do update"), "the delta must never update rows the nightly masters owns");
  assert.match(sql, /insert into coldlion\.sync_run[^;]*'\/itemDetails'/s);
  assert.match(sql, new RegExp(DELTA_REQUESTED_BY));
  assert.match(sql, /insert into coldlion\.change_log[^;]*'item_header'/s);
  assert.match(sql, /insert into coldlion\.change_log[^;]*'item_detail'/s);
  assert.match(sql, /^begin;$/m);
  assert.match(sql, /^commit;$/m);
  assert.match(sql, /'PPK-X'/);
});

test("empty batches still produce runnable SQL with zero-count temp tables", () => {
  const sql = buildItemDetailDeltaSql({ run, headerRows: [], detailRows: [] });
  assert.match(sql, /create temp table _delta_headers_inserted on commit drop as select[^;]*where false;/);
  assert.match(sql, /create temp table _delta_item_detail_inserted on commit drop as select[^;]*where false;/);
  assert.match(sql, /\(select count\(\*\) from _delta_item_detail_inserted\)/);
  assert.ok(!sql.includes("values\n  (") || !sql.includes("insert into coldlion.item_header"), "no landing statements without rows");
});

test("parseExistingItemNumbers reads psql box output only between the rule and the footer", () => {
  const stdout = " btrim \n--------\n  A1 \n  A2\n(2 rows)\n";
  assert.deepEqual(parseExistingItemNumbers(stdout), ["A1", "A2"]);
  assert.deepEqual(parseExistingItemNumbers("no table"), []);
});

test("landNewItemDetails lands details before returning counts; a pathological feed lands nothing", async () => {
  const sqls = [];
  const runSqlImpl = (sql) => { sqls.push(sql); return " btrim \n--------\n A1 \n(1 row)\n"; };
  const fetchImpl = async () => ({ ok: true, json: async () => [{ companyCode: "EDGEHOME", divisionCode: "CW001", itemNo: "N1", itemPkey: "1", prePackCode: "PPK-X" }] });
  const landed = await landNewItemDetails("k", [payload("A1"), payload("N1")], { runSqlImpl, fetchImpl });
  assert.equal(landed.newItems, 1);
  assert.equal(landed.detailsLanded, 1);
  assert.deepEqual(landed.failures, []);
  assert.equal(sqls.length, 2);
  assert.match(sqls[1], /insert into coldlion\.item_detail/);

  const none = await landNewItemDetails("k", [payload("A1")], { runSqlImpl, fetchImpl });
  assert.equal(none.newItems, 0);
  assert.equal(sqls.length, 3, "the existing-items query still runs");
  assert.ok(!sqls[2].includes("insert into coldlion.item_detail"), "no landing statements when nothing is new");

  const many = Array.from({ length: MAX_DELTA_ITEMS + 1 }, (_, index) => payload(`B${index}`));
  const refused = await landNewItemDetails("k", many, { runSqlImpl, fetchImpl });
  assert.equal(refused.newItems, MAX_DELTA_ITEMS + 1);
  assert.equal(refused.detailsLanded, 0);
  assert.match(refused.refused, /delta cap/);
  assert.equal(sqls.length, 4, "a pathological feed runs no per-item GETs");
  assert.ok(!sqls[3].includes("insert into coldlion.item_detail"), "a pathological feed lands nothing");
});

test("a failed per-item detail fetch is reported, not fatal, and still lands the others", async () => {
  const runSqlImpl = () => " btrim \n--------\n A1 \n(1 row)\n";
  const fetchImpl = async (url) => {
    if (String(url).includes("itemNo=N2")) return { ok: false, status: 500, json: async () => ({}) };
    return { ok: true, json: async () => [{ companyCode: "EDGEHOME", divisionCode: "CW001", itemNo: "N1", itemPkey: "1", prePackCode: null }] };
  };
  const landed = await landNewItemDetails("k", [payload("N1"), payload("N2")], { runSqlImpl, fetchImpl });
  assert.equal(landed.detailsLanded, 1);
  assert.equal(landed.failures.length, 1);
  assert.equal(landed.failures[0].itemNo, "N2");
});
