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
// Shapes follow the masters loader exactly (review round 1 of this change):
//   - sync_run is inserted FIRST and finished last — item_header/item_detail/
//     change_log carry immediate FKs to it;
//   - source_hash is the sha256 of the canonical (sorted-keys) payload row and
//     new_raw is the verbatim payload, like load-masters;
//   - the delta never advances the auto-flow's evidence clock: that clock reads
//     only 'coldlion-landing sync-masters' runs, so a failed per-item pull still
//     defers to the next full masters projection instead of being wrongly
//     cleared by this delta landing other rows;
//   - INSERT-only with ON CONFLICT DO NOTHING — the nightly masters landing owns
//     updates and deletes; this delta only bridges the hours before it runs;
//   - vendor rows are validated against the requested scope before landing
//     (wrong item, wrong company/division, EP001, blank keys are dropped, never
//     fatal); EP001 detail rows do not exist by design (table CHECK).
// Landing failures abort only the delta transaction; the item import still runs.

import { COLDLION_BASE_URL } from "../../coldlion-sync-common.mjs";
import { sourceHash } from "./values.mjs";
import { sqlJson, sqlText, sqlTimestamp, sqlUuid } from "./values.mjs";

// A run that would treat more than this many items as new is not a normal
// delta (2-25/day is the measured nightly range) — it is a ColdLion-side
// anomaly and must not fan out into thousands of per-item GETs. Land nothing;
// the nightly masters run covers the items instead.
export const MAX_DELTA_ITEMS = 60;

export const DELTA_REQUESTED_BY = "coldlion-item-sweep";
export const DETAIL_FETCH_TIMEOUT_MS = 30_000;

const clean = (value) => String(value ?? "").trim();

// Newness is (company, division, itemNo) — item numbers repeat across
// divisions (20 measured live, 20260905014719), so an item_number-only test
// would starve cross-division new items of the instant path.
export function newItemsFromPayload(payloadItems, existingIdentities) {
  const existing = new Set(existingIdentities.map((parts) => parts.map(clean).join("\u0000")));
  return payloadItems.filter((row) => {
    if (!clean(row?.itemNo) || !clean(row?.companyCode) || !clean(row?.divisionCode)) return false;
    if (clean(row.divisionCode) === "EP001") return false; // masters lands no EP001 detail rows
    return !existing.has([row.companyCode, row.divisionCode, row.itemNo].map(clean).join("\u0000"));
  });
}

// A detail row is landable only when it belongs to the item that was asked for
// and carries a complete natural key; anything else is a vendor surprise and is
// reported, never landed.
export function validDetailRow(detail, request) {
  if (!clean(detail?.itemPkey) || !clean(detail?.itemNo)) return "blank natural key";
  if (clean(detail.companyCode) !== clean(request.companyCode)
    || clean(detail.divisionCode) !== clean(request.divisionCode)
    || clean(detail.itemNo) !== clean(request.itemNo)) return "row outside the requested scope";
  if (clean(detail.divisionCode) === "EP001") return "EP001 detail rows do not exist by design";
  return null;
}

export async function fetchItemDetails(apiKey, { companyCode, divisionCode, itemNo }, fetchImpl = fetch) {
  const url = new URL(`${COLDLION_BASE_URL}/itemDetails`);
  url.searchParams.set("companyCode", companyCode);
  url.searchParams.set("divisionCode", divisionCode);
  url.searchParams.set("itemNo", itemNo);
  const response = await fetchImpl(url, {
    headers: { "X-API-Key": apiKey },
    signal: AbortSignal.timeout(DETAIL_FETCH_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
  const payload = await response.json();
  if (!Array.isArray(payload)) throw new Error(`${url} returned a non-array body`);
  return payload;
}

// One transaction: sync_run first (FK parent), insert-only landing, then the
// finishing update with honest counts and a DB-visible failure note. The
// landing tables have no source_raw column — the verbatim payload lives in
// change_log.new_raw, joined back per landed key.
export function buildItemDetailDeltaSql({ run, headerRows, detailRows }) {
  const headerValues = headerRows
    .map((row) => `  (${sqlText(clean(row.companyCode))}, ${sqlText(clean(row.divisionCode))}, ${sqlText(clean(row.itemNo))}, ${sqlText(row.itemDesc)}, ${sqlUuid(run.id)}, ${sqlText(sourceHash(row))}, ${sqlTimestamp(run.fetchedAt)}, ${sqlTimestamp(run.fetchedAt)}, ${sqlTimestamp(run.fetchedAt)})`)
    .join(",\n");
  const headerEvidence = headerRows
    .map((row) => `  (${sqlText(clean(row.companyCode))}, ${sqlText(clean(row.divisionCode))}, ${sqlText(clean(row.itemNo))}, ${sqlText(sourceHash(row))}, ${sqlJson(row)})`)
    .join(",\n");
  const detailValues = detailRows
    .map((row) => `  (${sqlText(clean(row.companyCode))}, ${sqlText(clean(row.divisionCode))}, ${sqlText(clean(row.itemNo))}, ${sqlText(clean(row.itemPkey))}, ${sqlText(row.prePackCode == null ? null : clean(row.prePackCode))}, ${sqlText(sourceHash(row))}, ${sqlUuid(run.id)}, ${sqlTimestamp(run.fetchedAt)}, ${sqlTimestamp(run.fetchedAt)}, ${sqlTimestamp(run.fetchedAt)})`)
    .join(",\n");
  const detailEvidence = detailRows
    .map((row) => `  (${sqlText(clean(row.companyCode))}, ${sqlText(clean(row.divisionCode))}, ${sqlText(clean(row.itemNo))}, ${sqlText(clean(row.itemPkey))}, ${sqlText(sourceHash(row))}, ${sqlJson(row)})`)
    .join(",\n");
  return [
    "begin;",
    `insert into coldlion.sync_run (id, endpoint, company_code, division_code, request_params, status, requested_by, started_at, rows_fetched)`,
    `values (${sqlUuid(run.id)}, '/itemDetails', ${sqlText(run.companyCode)}, ${sqlText(run.divisionCode)}, ${sqlText(JSON.stringify(run.requestParams))}::jsonb, 'running', ${sqlText(run.requestedBy)}, ${sqlTimestamp(run.startedAt)}, ${detailRows.length});`,
    headerRows.length
      ? [
          "insert into coldlion.item_header (company_code, division_code, item_no, item_desc, run_id, source_hash, fetched_at, first_seen_at, last_seen_at)",
          "values",
          headerValues,
          "on conflict (company_code, division_code, item_no) do nothing;",
          "create temp table _delta_headers_inserted on commit drop as",
          "with ins as (",
          "  select v.company_code, v.division_code, v.item_no, v.source_hash, v.raw",
          "  from (values",
          headerEvidence,
          `  ) as v(company_code, division_code, item_no, source_hash, raw)`,
          "  join coldlion.item_header hd using (company_code, division_code, item_no)",
          `  where hd.run_id = ${sqlUuid(run.id)}`,
          ") select * from ins;",
          "insert into coldlion.change_log (table_name, natural_key, change_kind, new_source_hash, new_raw, run_id)",
          `select 'item_header', jsonb_build_object('company_code', h.company_code, 'division_code', h.division_code, 'item_no', h.item_no), 'inserted', h.source_hash, h.raw, ${sqlUuid(run.id)}`,
          "  from _delta_headers_inserted h;",
        ].join("\n")
      : "select 'no new item headers to land' as note;",
    detailRows.length
      ? [
          "create temp table _delta_item_detail_inserted on commit drop as",
          "with ins as (",
          "  insert into coldlion.item_detail (company_code, division_code, item_no, item_pkey, pre_pack_code, source_hash, run_id, fetched_at, first_seen_at, last_seen_at)",
          "  values",
          detailValues,
          "  on conflict (company_code, division_code, item_no, item_pkey) do nothing",
          "  returning company_code, division_code, item_no, item_pkey",
          ") select * from ins;",
          "insert into coldlion.change_log (table_name, natural_key, change_kind, new_source_hash, new_raw, run_id)",
          "select 'item_detail', jsonb_build_object('company_code', v.company_code, 'division_code', v.division_code, 'item_no', v.item_no, 'item_pkey', v.item_pkey), 'inserted', v.source_hash, v.raw, " + sqlUuid(run.id),
          "  from (values",
          detailEvidence,
          "  ) as v(company_code, division_code, item_no, item_pkey, source_hash, raw)",
          "  join _delta_item_detail_inserted d using (company_code, division_code, item_no, item_pkey);",
        ].join("\n")
      : "create temp table _delta_item_detail_inserted on commit drop as select null::text as company_code, null::text as division_code, null::text as item_no, null::text as item_pkey where false;",
    `update coldlion.sync_run set status = 'succeeded', finished_at = ${sqlTimestamp(run.fetchedAt)},`,
    `  rows_inserted = coalesce((select count(*) from _delta_item_detail_inserted), 0),`,
    `  notes = ${sqlText(JSON.stringify(run.notes ?? {}))}`,
    ` where id = ${sqlUuid(run.id)};`,
    "commit;",
    "",
  ].join("\n");
}
