#!/usr/bin/env node

// #5011: the new-item heartbeat. A few tiny GETs per 5 minutes ask ColdLion
// "any items created since <window>?" via /items?createdFrom=...&size=1, and
// the workflow dispatches the existing item sweep (delta details + import +
// Master Data auto-flow) only when the answer is yes — replacing the old
// 30-minute full sweep.
//
// RECORDED LIVE EVIDENCE for the filter (2026-10-29, read-only, production
// ColdLion, issue #5011; "record the probe or it is fabricated"):
//   control (no filter)            totalElements=19862
//   createdFrom=<ISO dt, 15m ago>  totalElements=0      HTTP 200 — format accepted
//   createdFrom=<ISO dt, tomorrow> totalElements=0      HTTP 200 — future is empty
//   createdFrom=2020-01-01T00:00Z  totalElements=15868  — NOT the control count,
//                                                       so the filter genuinely filters
//   modifiedFrom=<same values>     identical totals to createdFrom on every
//                                  probe — the vendor serves createdFrom semantics
//                                  for modifiedFrom, so an edit-coverage probe via
//                                  modifiedFrom is fiction and is NOT used.
// Consequence named on #5011: item EDITS (not creations) now land at the three
// anchor sweeps plus the nightly masters run instead of every 30 minutes.
//
// Self-checks run every cycle (B2): a future-date filter must be empty and an
// old-date filter must be non-empty and sane, so a vendor change that starts
// ignoring or silently rejecting the filter fails LOUDLY instead of blind-green
// or hammering.

import { pathToFileURL } from "node:url";
import { COLDLION_BASE_URL, readColdlionApiKey } from "./coldlion-sync-common.mjs";

// Just over the 5-minute cadence: a delayed or skipped run still sees the next
// run's window, while a single creation triggers at most one extra dispatch
// (the workflow additionally throttles dispatches to one sweep per 10 minutes).
export const HEARTBEAT_WINDOW_MINUTES = 6;
export const HEARTBEAT_MAX_NEW_ITEMS = 500;
export const HEARTBEAT_SANITY_CEILING = 50_000;
export const HEARTBEAT_ANCHOR_DATE = "2020-01-01T00:00:00.000Z";
export const HEARTBEAT_FETCH_TIMEOUT_MS = 10_000;

function itemUrl(params, { baseUrl = COLDLION_BASE_URL } = {}) {
  const url = new URL(`${baseUrl}/items`);
  url.searchParams.set("companyCode", "EDGEHOME");
  for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
  url.searchParams.set("size", "1");
  url.searchParams.set("page", "0");
  return url;
}

export function buildHeartbeatUrls({ now = new Date(), baseUrl = COLDLION_BASE_URL, windowMinutes = HEARTBEAT_WINDOW_MINUTES } = {}) {
  const since = new Date(now.getTime() - windowMinutes * 60_000).toISOString();
  const future = new Date(now.getTime() + 24 * 3600 * 1000).toISOString();
  return {
    window: itemUrl({ createdFrom: since }, { baseUrl }),
    futureEmpty: itemUrl({ createdFrom: future }, { baseUrl }),
    oldNonEmpty: itemUrl({ createdFrom: HEARTBEAT_ANCHOR_DATE }, { baseUrl }),
  };
}

// size=1 responses carry their truth in totalElements; the single content row
// is only a sample. An envelope without totalElements is a shape change (L1):
// fail loudly rather than silently fall back to the capped page length.
export function classifyHeartbeat(payload, { maxNewItems = HEARTBEAT_MAX_NEW_ITEMS, sanityCeiling = HEARTBEAT_SANITY_CEILING } = {}) {
  const rows = Array.isArray(payload) ? payload : payload?.content;
  if (!Array.isArray(rows)) return { outcome: "malformed", message: "response is neither an array nor a paged content envelope" };
  const total = Array.isArray(payload) ? rows.length : payload?.totalElements;
  if (!Number.isFinite(total)) return { outcome: "malformed", message: "paged envelope carries no totalElements; refusing to guess from a size=1 page" };
  if (total > maxNewItems) {
    return { outcome: "filter-suspected", message: `the time filter matched ${total} items — the filter appears ignored; refusing to trigger a full sweep every five minutes` };
  }
  if (total === 0) return { outcome: "quiet", newItems: 0 };
  return { outcome: "trigger", newItems: total, itemNumbers: rows.map((row) => String(row?.itemNo ?? "").trim()).filter(Boolean) };
}

export function classifySelfChecks(futureResult, oldResult, { sanityCeiling = HEARTBEAT_SANITY_CEILING } = {}) {
  if (futureResult.outcome !== "quiet") {
    return { outcome: "filter-suspected", message: `a future-dated createdFrom must be empty but returned ${futureResult.newItems ?? "?"} — the filter appears ignored` };
  }
  if (oldResult.outcome !== "trigger" || !Number.isFinite(oldResult.newItems) || oldResult.newItems <= 0 || oldResult.newItems > sanityCeiling) {
    return { outcome: "malformed", message: `an old-dated createdFrom must return a sane non-empty count but gave ${JSON.stringify(oldResult.newItems ?? oldResult)} — the filter appears rejected or misread` };
  }
  return { outcome: "ok" };
}

async function main() {
  const apiKey = readColdlionApiKey();
  const urls = buildHeartbeatUrls();
  const results = {};
  for (const [kind, url] of Object.entries(urls)) {
    const response = await fetch(url, { headers: { "X-API-Key": apiKey }, signal: AbortSignal.timeout(HEARTBEAT_FETCH_TIMEOUT_MS) });
    if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
    results[kind] = { url: String(url), ...classifyHeartbeat(await response.json()) };
  }
  const selfCheck = classifySelfChecks(results.futureEmpty, results.oldNonEmpty);
  const trigger = results.window.outcome === "trigger";
  const bad = selfCheck.outcome !== "ok" || results.window.outcome === "filter-suspected" || results.window.outcome === "malformed";
  process.stdout.write(`${JSON.stringify({ checkedAt: new Date().toISOString(), trigger, selfCheck, window: results.window }, null, 2)}\n`);
  if (bad) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`Coldlion item heartbeat failed: ${error.stack ?? error}\n`);
    process.exitCode = 1;
  });
}
