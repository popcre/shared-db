#!/usr/bin/env node

import { randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";
import {
  COLDLION_BASE_URL,
  buildFailedSyncRunSql,
  fetchPaged,
  readColdlionApiKey,
  runSql,
  sqlDollarQuote,
} from "./coldlion-sync-common.mjs";
import { assertExpectedTarget } from "./coldlion-landing/lib/db.mjs";

export function buildItemImportPayload(items, options = {}) {
  return {
    sweepId: options.sweepId ?? randomUUID(),
    terminalReached: options.terminalReached === true,
    minimumSilverRatio: options.minimumSilverRatio ?? 0.8,
    items,
  };
}

// Refuse to promote a sweep that collapses licensor resolution (#3903 review F2): a
// stale or empty merch-group header dictionary resolves nothing, and the upsert
// would overwrite previously resolved licensor/property links with NULL while every
// row-count guard still passes. runSql applies the script as ONE transaction, so the
// raise rolls the whole import back.
export const MIN_RESOLVED_RETENTION = 0.9;

export function buildItemImportSql(payload) {
  return [
    "create temp table item_master_resolved_before on commit drop as",
    "  select count(*)::bigint as n from plm.item where source_system = 'coldlion' and licensor_id is not null;",
    `select * from plm.import_item_master_data(${sqlDollarQuote("cl_items", payload)}::jsonb);`,
    "do $guard$",
    "declare v_before bigint; v_after bigint;",
    "begin",
    "  select n into v_before from item_master_resolved_before;",
    "  select count(*) into v_after from plm.item where source_system = 'coldlion' and licensor_id is not null;",
    `  if v_before > 0 and v_after < v_before * ${MIN_RESOLVED_RETENTION} then`,
    "    raise exception 'item master resolution collapsed: % -> % resolved items; refusing to promote', v_before, v_after;",
    "  end if;",
    "end",
    "$guard$;",
    "",
  ].join("\n");
}

const KNOWN_FLAGS = new Set(["--apply", "--linked"]);

/** A misspelled flag must fail loudly, never degrade into a green fetch-only run. */
export function parseLoaderArgs(argv, known = KNOWN_FLAGS) {
  const unknown = argv.filter((arg) => !known.has(arg));
  if (unknown.length) throw new Error(`unknown argument(s): ${unknown.join(" ")}; allowed: ${[...known].join(" ")}`);
  return { apply: argv.includes("--apply"), linked: argv.includes("--linked") };
}

export async function collectItems(apiKey, fetchImpl = fetch) {
  const url = new URL(`${COLDLION_BASE_URL}/items`);
  url.searchParams.set("companyCode", "EDGEHOME");
  url.searchParams.set("size", "200");
  return fetchPaged(url, apiKey, fetchImpl);
}

async function main() {
  const { apply, linked } = parseLoaderArgs(process.argv.slice(2));
  if (apply && !linked) assertExpectedTarget();
  let stage = "fetch";
  try {
    const sweep = await collectItems(readColdlionApiKey());
    const payload = buildItemImportPayload(sweep.rows, sweep);
    const divisions = sweep.rows.reduce((counts, row) => {
      counts[row.divisionCode ?? "(missing)"] = (counts[row.divisionCode ?? "(missing)"] ?? 0) + 1;
      return counts;
    }, {});
    process.stdout.write(`${JSON.stringify({ items: sweep.rows.length, pagesFetched: sweep.pagesFetched,
      terminalReached: sweep.terminalReached, divisions, apply }, null, 2)}\n`);
    if (apply) {
      stage = "apply";
      process.stdout.write(runSql(buildItemImportSql(payload), { linked }));
    }
  } catch (error) {
    if (apply) {
      try { runSql(buildFailedSyncRunSql("item_taxonomy_resolver", stage, error.message), { linked }); }
      catch (recordError) { process.stderr.write(`WARNING: failed to record durable failure: ${recordError.message}\n`); }
    }
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`Coldlion item sync failed: ${error.stack ?? error}\n`);
    process.exitCode = 1;
  });
}
