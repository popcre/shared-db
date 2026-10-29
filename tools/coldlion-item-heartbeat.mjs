#!/usr/bin/env node

// #5011: the new-item heartbeat. One tiny GET per 5 minutes that asks ColdLion
// "any items created since <window>?" via /items?createdFrom=..., and says
// TRIGGER only when the answer is yes — the full sweep (delta details + import
// + Master Data auto-flow) then runs on demand instead of on a 30-minute
// timer. Load math versus the old schedule lives in the workflow comments.
//
// Vendor-defect guard: if the filter is ignored (the /seasons defect class),
// the response is the whole item master. A response that large is never a
// real 15-minute delta, so the probe fails loudly instead of triggering a
// full sweep every five minutes.

import { pathToFileURL } from "node:url";
import { COLDLION_BASE_URL, readColdlionApiKey } from "./coldlion-sync-common.mjs";

// Overlap deliberately exceeds the 5-minute cadence: a skipped or delayed run
// still sees the next run's window, and the sweep itself is idempotent.
export const HEARTBEAT_WINDOW_MINUTES = 15;
export const HEARTBEAT_MAX_NEW_ITEMS = 500;

export function buildHeartbeatUrl({ now = new Date(), baseUrl = COLDLION_BASE_URL, windowMinutes = HEARTBEAT_WINDOW_MINUTES } = {}) {
  const url = new URL(`${baseUrl}/items`);
  url.searchParams.set("companyCode", "EDGEHOME");
  url.searchParams.set("createdFrom", new Date(now.getTime() - windowMinutes * 60_000).toISOString());
  url.searchParams.set("size", "50");
  url.searchParams.set("page", "0");
  return url;
}

export function classifyHeartbeat(payload, { maxNewItems = HEARTBEAT_MAX_NEW_ITEMS } = {}) {
  const rows = Array.isArray(payload) ? payload : payload?.content;
  if (!Array.isArray(rows)) return { outcome: "malformed", message: "response is neither an array nor a paged content envelope" };
  if (rows.length > maxNewItems) {
    return { outcome: "filter-suspected", message: `createdFrom returned ${rows.length} rows — the filter appears ignored; refusing to trigger a full sweep every five minutes` };
  }
  if (rows.length === 0) return { outcome: "quiet", newItems: 0 };
  return { outcome: "trigger", newItems: rows.length, itemNumbers: rows.map((row) => String(row?.itemNo ?? "").trim()).filter(Boolean) };
}

async function main() {
  const apiKey = readColdlionApiKey();
  const url = buildHeartbeatUrl();
  const response = await fetch(url, { headers: { "X-API-Key": apiKey } });
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
  const result = classifyHeartbeat(await response.json());
  process.stdout.write(`${JSON.stringify({ url: String(url), checkedAt: new Date().toISOString(), ...result }, null, 2)}\n`);
  if (result.outcome === "filter-suspected") process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`Coldlion item heartbeat failed: ${error.stack ?? error}\n`);
    process.exitCode = 1;
  });
}
