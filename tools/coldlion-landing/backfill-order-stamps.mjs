#!/usr/bin/env node
// One-off, re-runnable backfill of ColdLion's sales-order entry/edit stamps (issue #3869).
//
//   node tools/coldlion-landing/backfill-order-stamps.mjs --from 2019-01-01 [--to 2026-10-04] [--dry-run]
//
// coldlion.order_history_line gained created_time / created_user / mod_time / mod_user on
// 2026-10-09 (migration 20261009170724). The window loader lands them for every window it
// loads from now on, but a loaded window is sealed and never re-read, so the rows landed
// before that date stay NULL. This walks the same 7-day start-date windows, re-reads
// /orderHistory, and UPDATES only those four columns. It inserts nothing, writes no page
// evidence and no ledger state, and touches no other column, so it cannot disturb the
// loader's sealed evidence.
//
// Grain follows the loader's line identity. On the current table shape (20260905105038)
// a landed line is (sales_order_no, sales_order_line_no, master_item_no, ...), so stamps are
// folded and matched on (sales order, line number, item); every version (line_source_hash)
// of that line receives the line's stamps. The older phases-2-6 shape some databases still
// carry (20260825023430, e.g. the DesignFlow sandbox) has no line number: its identity is
// (sales_order_no, item_no, label_code, ...), and that is the grain used there. The tool
// detects the shape. Within one key the EARLIEST created_time and the LATEST mod_time win
// (with the user who made each) -- the rule the loader applies across a line's components. Each window commits on its own, so an
// interrupted run is resumed simply by running it again.
//
// Needs DATABASE_URL, COLDLION_EXPECTED_PROJECT_REF and the ColdLion API key, exactly as
// the other loaders. Never schedule this: ongoing loads already carry the stamps.

import { readColdlionApiKey } from "../coldlion-sync-common.mjs";
import { isoDate, lastClosedWindowIndex, windowAtIndex, windowRange } from "./lib/grid.mjs";
import { proveTarget, queryRows, runSql } from "./lib/db.mjs";
import { fetchWindowScope } from "./lib/http.mjs";
import { mergeLineStamps, projectLineStamps } from "./lib/project-order-history.mjs";
import { COMPANY_CODE, ORDER_HISTORY } from "./lib/scopes.mjs";
import { bigint, sqlText, sqlTimestamp, text } from "./lib/values.mjs";

export function parseArgs(argv) {
  const args = { company: COMPANY_CODE, dryRun: false };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];
    switch (flag) {
      case "--from": args.from = value; index += 1; break;
      case "--to": args.to = value; index += 1; break;
      case "--company": args.company = value; index += 1; break;
      case "--dry-run": args.dryRun = true; break;
      default: throw new Error(`unknown argument ${flag}`);
    }
  }
  if (!args.from) throw new Error("--from is required");
  if (!args.to) args.to = windowAtIndex(lastClosedWindowIndex(isoDate(new Date()))).to;
  return args;
}

export const SHAPES = Object.freeze({
  // current: identity (sales_order_no, sales_order_line_no, master_item_no, line_source_hash)
  current: { itemColumn: "master_item_no", lineNo: true },
  // legacy phases-2-6: identity (sales_order_no, item_no, label_code, line_source_hash)
  legacy: { itemColumn: "item_no", lineNo: false },
});

function shapeOf(name) {
  const shape = SHAPES[name];
  if (!shape) throw new Error(`unexpected table shape ${name}`);
  return shape;
}

/** Fold vendor rows into one stamp set per landed-line key of the given table shape. */
export function aggregateStamps(rows, shapeName) {
  const shape = shapeOf(shapeName);
  const keyed = new Map();
  for (const row of rows) {
    const salesOrderNo = bigint(row.salesOrderNo);
    const itemNo = text(row.itemNo);
    if (salesOrderNo === null || itemNo === null) continue;
    const lineNo = shape.lineNo ? bigint(row.salesOrderLineNo) : null;
    if (shape.lineNo && lineNo === null) throw new Error("an orderHistory row has no salesOrderLineNo");
    const labelCode = shape.lineNo ? null : text(row.labelCode);
    const key = JSON.stringify([salesOrderNo, lineNo, itemNo, labelCode]);
    let entry = keyed.get(key);
    if (!entry) {
      entry = { sales_order_no: salesOrderNo, sales_order_line_no: lineNo, item_no: itemNo, label_code: labelCode,
                created_time: null, created_user: null, mod_time: null, mod_user: null };
      keyed.set(key, entry);
    }
    mergeLineStamps(entry, projectLineStamps(row));
  }
  return [...keyed.values()].filter((entry) => entry.created_time !== null || entry.mod_time !== null);
}

/** One transaction: stage the stamps, update only rows whose stamps differ. */
export function buildStampUpdateSql(stamps, shapeName) {
  const shape = shapeOf(shapeName);
  if (stamps.length === 0) return null;
  const values = stamps
    .map((s) => `(${s.sales_order_no}::bigint, ${s.sales_order_line_no === null ? "null" : Number(s.sales_order_line_no)}::bigint, ${sqlText(s.item_no)}, ${sqlText(s.label_code)}::text, ${sqlTimestamp(s.created_time)}, ${sqlText(s.created_user)}::text, ${sqlTimestamp(s.mod_time)}, ${sqlText(s.mod_user)}::text)`)
    .join(",\n");
  const grain = shape.lineNo
    ? `and t.sales_order_line_no = s.sales_order_line_no
   and t.master_item_no = s.item_no`
    : `and t.item_no = s.item_no
   and t.label_code is not distinct from s.label_code`;
  return `begin;
create temp table _stamps (sales_order_no bigint, sales_order_line_no bigint, item_no text, label_code text,
  created_time timestamptz, created_user text, mod_time timestamptz, mod_user text) on commit drop;
insert into _stamps values
${values};
update coldlion.order_history_line t
   set created_time = s.created_time, created_user = s.created_user,
       mod_time = s.mod_time, mod_user = s.mod_user
  from _stamps s
 where t.sales_order_no = s.sales_order_no
   ${grain}
   and (t.created_time, t.created_user, t.mod_time, t.mod_user)
       is distinct from (s.created_time, s.created_user, s.mod_time, s.mod_user);
commit;`;
}

export function detectShape(options = {}) {
  const rows = queryRows(
    `select attname from pg_attribute
      where attrelid = 'coldlion.order_history_line'::regclass and not attisdropped
        and attname in ('master_item_no', 'sales_order_line_no', 'item_no', 'label_code', 'created_time');`,
    options,
  ).map(([name]) => name);
  if (!rows.includes("created_time")) {
    throw new Error("coldlion.order_history_line has no created_time; apply migration 20261009170724 first");
  }
  if (rows.includes("master_item_no") && rows.includes("sales_order_line_no")) return "current";
  if (rows.includes("item_no") && rows.includes("label_code")) return "legacy";
  throw new Error("coldlion.order_history_line matches neither known table shape");
}

export async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const windows = [...windowRange(args.from, args.to)];
  console.log(`${windows.length} window(s) ${args.from}..${args.to}`);
  if (args.dryRun) return { windows: windows.length };
  const target = proveTarget();
  console.log(`target ${target.database} at ${target.host} (${target.coldlionTables} coldlion tables)`);
  const shape = detectShape();
  const apiKey = readColdlionApiKey();
  let done = 0;
  for (const window of windows) {
    const { pages } = await fetchWindowScope({ scope: ORDER_HISTORY, window, apiKey, companyCode: args.company });
    const stamps = aggregateStamps(pages.flatMap((page) => page.content), shape);
    const sql = buildStampUpdateSql(stamps, shape);
    if (sql) runSql(sql);
    done += 1;
    console.log(`${window.from}..${window.to} ${stamps.length} stamped key(s) [${done}/${windows.length}]`);
  }
  return { windows: windows.length };
}

if (process.argv[1]?.endsWith("backfill-order-stamps.mjs")) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
