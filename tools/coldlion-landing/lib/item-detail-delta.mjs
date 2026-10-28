// #4974: per-item /itemDetails delta for the 30-minute item sweep.
//
// The nightly masters landing is the only full writer of coldlion.item_detail,
// which left the Master Data auto-flow (#4956) deciding brand-new items on
// stale evidence until the next 05:20 UTC run. ColdLion's /itemDetails endpoint
// accepts companyCode/divisionCode/itemNo filters
// (docs/coldlion-erp-api-reference.md), so the sweep pulls the detail rows of
// each NEW item in the same cycle, BEFORE the import SQL runs: the assortment
// marker (pre_pack_code) is then already on the row the auto-flow reads, and a
// new assortment is skipped instantly instead of after the nightly landing.
//
// Deliberately INSERT-only with ON CONFLICT DO NOTHING: the nightly masters
// landing owns updates and deletes for these tables; this delta only bridges
// the hours before it runs. EP001 detail rows are excluded exactly like the
// masters pull (coldlion.item_detail check constraint). change_log and
// sync_run rows follow the masters shapes so the audit spine stays complete:
// source_hash is the sha256 of the verbatim payload row and new_raw is that
// row itself.

import { createHash } from "node:crypto";
import { COLDLION_BASE_URL } from "../../coldlion-sync-common.mjs";
import { sqlText, sqlTimestamp, sqlUuid } from "./values.mjs";

// A run that would treat more than this many items as new is not a normal
// delta (2-25/day is the measured nightly range) — it is a ColdLion-side
// anomaly and must not fan out into thousands of per-item GETs. Land nothing;
// the nightly masters run covers the items instead.
export const MAX_DELTA_ITEMS = 60;

export const DELTA_REQUESTED_BY = "coldlion-item-sweep";

export function newItemsFromPayload(payloadItems, existingItemNumbers) {
  const existing = new Set(existingItemNumbers.map((value) => String(value ?? "").trim()).filter(Boolean));
  return payloadItems.filter((row) => {
    const itemNo = String(row?.itemNo ?? "").trim();
    if (!itemNo) return false;
    if (String(row?.divisionCode ?? "").trim() === "EP001") return false; // masters lands no EP001 detail rows
    return !existing.has(itemNo);
  });
}

export async function fetchItemDetails(apiKey, { companyCode, divisionCode, itemNo }, fetchImpl = fetch) {
  const url = new URL(`${COLDLION_BASE_URL}/itemDetails`);
  url.searchParams.set("companyCode", companyCode);
  url.searchParams.set("divisionCode", divisionCode);
  url.searchParams.set("itemNo", itemNo);
  const response = await fetchImpl(url, { headers: { "X-API-Key": apiKey } });
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
  const payload = await response.json();
  if (!Array.isArray(payload)) throw new Error(`${url} returned a non-array body`);
  return payload;
}

const rowHash = (row) => createHash("sha256").update(JSON.stringify(row)).digest("hex");
const rawJson = (row) => `${sqlText(JSON.stringify(row))}::jsonb`;

// One transaction: insert-only landing, then sync_run bookkeeping. Existing
// rows are left untouched (masters owns them). Empty batches keep the
// temp-table shapes so the sync_run counts below always resolve.
export function buildItemDetailDeltaSql({ run, headerRows, detailRows }) {
  const headerValues = headerRows
    .map((row) => `  (${sqlText(row.companyCode)}, ${sqlText(row.divisionCode)}, ${sqlText(row.itemNo)}, ${sqlText(row.itemDesc)}, ${sqlUuid(run.id)}, ${sqlText(rowHash(row))}, ${sqlTimestamp(run.fetchedAt)}, ${sqlTimestamp(run.fetchedAt)}, ${sqlTimestamp(run.fetchedAt)})`)
    .join(",\n");
  const detailValues = detailRows
    .map((row) => `  (${sqlText(row.companyCode)}, ${sqlText(row.divisionCode)}, ${sqlText(row.itemNo)}, ${sqlText(row.itemPkey)}, ${sqlText(row.prePackCode)}, ${sqlUuid(run.id)}, ${sqlText(rowHash(row))}, ${sqlTimestamp(run.fetchedAt)}, ${sqlTimestamp(run.fetchedAt)}, ${sqlTimestamp(run.fetchedAt)})`)
    .join(",\n");
  return [
    "begin;",
    headerRows.length
      ? [
          "create temp table _delta_headers_inserted on commit drop as",
          "with ins as (",
          "  insert into coldlion.item_header (company_code, division_code, item_no, item_desc, run_id, source_hash, fetched_at, first_seen_at, last_seen_at)",
          "  values",
          headerValues,
          "  on conflict (company_code, division_code, item_no) do nothing",
          "  returning company_code, division_code, item_no",
          ") select * from ins;",
          "insert into coldlion.change_log (table_name, natural_key, change_kind, new_source_hash, new_raw, run_id)",
          "select 'item_header', jsonb_build_object('company_code', h.company_code, 'division_code', h.division_code, 'item_no', h.item_no), 'inserted',",
          `       hd.source_hash, to_jsonb(hd) - array['run_id', 'source_hash', 'fetched_at', 'first_seen_at', 'last_seen_at']::text[], ${sqlUuid(run.id)}`,
          "  from _delta_headers_inserted h",
          "  join coldlion.item_header hd on hd.company_code = h.company_code and hd.division_code = h.division_code and hd.item_no = h.item_no;",
        ].join("\n")
      : "create temp table _delta_headers_inserted on commit drop as select null::text as company_code, null::text as division_code, null::text as item_no where false;",
    detailRows.length
      ? [
          "create temp table _delta_item_detail_inserted on commit drop as",
          "with ins as (",
          "  insert into coldlion.item_detail (company_code, division_code, item_no, item_pkey, pre_pack_code, run_id, source_hash, fetched_at, first_seen_at, last_seen_at)",
          "  values",
          detailValues,
          "  on conflict (company_code, division_code, item_no, item_pkey) do nothing",
          "  returning company_code, division_code, item_no, item_pkey",
          ") select * from ins;",
          "insert into coldlion.change_log (table_name, natural_key, change_kind, new_source_hash, new_raw, run_id)",
          "select 'item_detail', jsonb_build_object('company_code', d.company_code, 'division_code', d.division_code, 'item_no', d.item_no, 'item_pkey', d.item_pkey), 'inserted',",
          `       dd.source_hash, to_jsonb(dd) - array['run_id', 'source_hash', 'fetched_at', 'first_seen_at', 'last_seen_at']::text[], ${sqlUuid(run.id)}`,
          "  from _delta_item_detail_inserted d",
          "  join coldlion.item_detail dd on dd.company_code = d.company_code and dd.division_code = d.division_code and dd.item_no = d.item_no and dd.item_pkey = d.item_pkey;",
        ].join("\n")
      : "create temp table _delta_item_detail_inserted on commit drop as select null::text as company_code, null::text as division_code, null::text as item_no, null::text as item_pkey where false;",
    "insert into coldlion.sync_run (id, endpoint, company_code, division_code, request_params, status, requested_by, started_at, finished_at, rows_fetched, rows_inserted)",
    `values (${sqlUuid(run.id)}, '/itemDetails', ${sqlText(run.companyCode)}, ${sqlText(run.divisionCode)}, ${sqlText(JSON.stringify(run.requestParams))}::jsonb, 'succeeded', ${sqlText(run.requestedBy)}, ${sqlTimestamp(run.fetchedAt)}, ${sqlTimestamp(run.fetchedAt)}, ${detailRows.length}, (select count(*) from _delta_item_detail_inserted));`,
    "commit;",
    "",
  ].join("\n");
}
