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
// The threshold reads the envelope's totalElements when present — the page is
// capped at 50 rows, so page length alone cannot see an ignored filter.
export const HEARTBEAT_MAX_NEW_ITEMS = 500;

function buildUrl(filterField, { now, baseUrl, windowMinutes }) {
  const url = new URL(`${baseUrl}/items`);
  url.searchParams.set("companyCode", "EDGEHOME");
  url.searchParams.set(filterField, new Date(now.getTime() - windowMinutes * 60_000).toISOString());
  url.searchParams.set("size", "50");
  url.searchParams.set("page", "0");
  return url;
}

// Two probes: createdFrom for new items, modifiedFrom for edits (the 30-minute
// sweep used to land both within half an hour; the anchors alone would stretch
// edits to ~6 hours). Sending both filters on one request would depend on the
// vendor's AND/OR semantics, so each filter gets its own tiny GET.
export function buildHeartbeatUrls({ now = new Date(), baseUrl = COLDLION_BASE_URL, windowMinutes = HEARTBEAT_WINDOW_MINUTES } = {}) {
  return {
    created: buildUrl("createdFrom", { now, baseUrl, windowMinutes }),
    modified: buildUrl("modifiedFrom", { now, baseUrl, windowMinutes }),
  };
}

export function classifyHeartbeat(payload, { maxNewItems = HEARTBEAT_MAX_NEW_ITEMS } = {}) {
  const rows = Array.isArray(payload) ? payload : payload?.content;
  if (!Array.isArray(rows)) return { outcome: "malformed", message: "response is neither an array nor a paged content envelope" };
  // totalElements is the filter's true match count; rows is one capped page.
  const matched = Number.isFinite(payload?.totalElements) ? payload.totalElements : rows.length;
  if (matched > maxNewItems) {
    return { outcome: "filter-suspected", message: `the time filter matched ${matched} items — the filter appears ignored; refusing to trigger a full sweep every five minutes` };
  }
  if (matched === 0) return { outcome: "quiet", newItems: 0 };
  return { outcome: "trigger", newItems: matched, itemNumbers: rows.map((row) => String(row?.itemNo ?? "").trim()).filter(Boolean) };
}

async function main() {
  const apiKey = readColdlionApiKey();
  const urls = buildHeartbeatUrls();
  const results = {};
  for (const [kind, url] of Object.entries(urls)) {
    const response = await fetch(url, { headers: { "X-API-Key": apiKey } });
    if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
    results[kind] = { url: String(url), ...classifyHeartbeat(await response.json()) };
  }
  const trigger = Object.values(results).some((result) => result.outcome === "trigger");
  const suspected = Object.values(results).some((result) => result.outcome === "filter-suspected");
  const malformed = Object.values(results).some((result) => result.outcome === "malformed");
  process.stdout.write(`${JSON.stringify({ checkedAt: new Date().toISOString(), trigger, ...results }, null, 2)}\n`);
  // A vendor surprise (ignored filter or changed envelope shape) must fail the
  // run loudly — a green-but-blind heartbeat is worse than a red one.
  if (suspected || malformed) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`Coldlion item heartbeat failed: ${error.stack ?? error}\n`);
    process.exitCode = 1;
  });
}
