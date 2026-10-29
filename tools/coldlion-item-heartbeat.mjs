#!/usr/bin/env node

// #5011: the new-item heartbeat. Tiny GETs every 5 minutes ask ColdLion "any
// items created since <window>?" via /items?createdFrom=...&size=1, and the
// workflow dispatches the existing item sweep (delta details + import + Master
// Data auto-flow) only when the answer is yes — replacing the old 30-minute
// full sweep.
//
// RECORDED LIVE EVIDENCE for the filter (2026-10-29, read-only, production
// ColdLion, issue #5011; "record the probe or it is fabricated"). The evidence
// probes used a 15-minute window; the live window below is 6 minutes:
//   control (no filter)            totalElements=19862
//   createdFrom=<ISO dt, recent>   totalElements=0      HTTP 200 — format accepted
//   createdFrom=<ISO dt, tomorrow> totalElements=0      HTTP 200 — future is empty
//   createdFrom=2020-01-01T00:00Z  totalElements=15868  — NOT the control count,
//                                                       so the filter genuinely filters
//   modifiedFrom=<same values>     identical totals to createdFrom on every
//                                  probe — the vendor serves createdFrom
//                                  semantics for modifiedFrom, so an
//                                  edit-coverage probe via it is fiction and
//                                  is NOT used. Known trade-off, recorded on
//                                  #5011: item edits now land at the three
//                                  anchor sweeps plus the nightly masters run
//                                  instead of every 30 minutes.
//
// Self-checks (B2, hardened round 3): the future-dated probe must be EMPTY
// (catches an ignored filter — the whole master would match) and the
// old-dated anchor probe must be NON-EMPTY (catches silent rejection to
// empty). The anchor's 15,868 is EXPECTED — it is classified by its own rule,
// never by the window's 500-item trigger threshold (round-3 B1). The anchor
// probe runs in the first 10 minutes of each half-hour only, so the vendor
// serves one big-match count query per 30 minutes, not per 5 (round-3 L1).
// A vendor surprise fails LOUDLY: a green-but-blind heartbeat is worse than
// a red one.

import { pathToFileURL } from "node:url";
import { COLDLION_BASE_URL, readColdlionApiKey } from "./coldlion-sync-common.mjs";

// Just over the 5-minute cadence: a delayed or skipped run still sees the next
// run's window, while a single creation triggers at most one extra dispatch
// (the workflow additionally throttles dispatches to one sweep per 10 minutes).
export const HEARTBEAT_WINDOW_MINUTES = 6;
export const HEARTBEAT_MAX_NEW_ITEMS = 500;
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
  const anchorDue = now.getUTCMinutes() < 10 || (now.getUTCMinutes() >= 30 && now.getUTCMinutes() < 40);
  return {
    window: itemUrl({ createdFrom: since }, { baseUrl }),
    futureEmpty: itemUrl({ createdFrom: future }, { baseUrl }),
    // Undefined means "not due this run" — the anchor runs once per half-hour.
    ...(anchorDue ? { anchorNonEmpty: itemUrl({ createdFrom: HEARTBEAT_ANCHOR_DATE }, { baseUrl }) } : {}),
  };
}

// The endpoint is paged; a bare array or an envelope without totalElements is
// a shape change and fails loudly — a size=1 page length can never stand in
// for the filter's true match count (round-2 L1, round-3 M1).
export function classifyHeartbeat(payload, { maxNewItems = HEARTBEAT_MAX_NEW_ITEMS } = {}) {
  const rows = payload?.content;
  if (!Array.isArray(rows) || !Number.isFinite(payload?.totalElements)) {
    return { outcome: "malformed", message: "response is not a paged envelope with content and totalElements; refusing to guess from a size=1 page" };
  }
  const total = payload.totalElements;
  if (total > maxNewItems) {
    return { outcome: "filter-suspected", message: `the time filter matched ${total} items — the filter appears ignored; refusing to trigger a full sweep every five minutes` };
  }
  if (total === 0) return { outcome: "quiet", newItems: 0 };
  return { outcome: "trigger", newItems: total, itemNumbers: rows.map((row) => String(row?.itemNo ?? "").trim()).filter(Boolean) };
}

// The anchor is judged only by "did the filter return a non-empty result".
// Its count is naturally tens of thousands — no ceiling constant, because a
// fixed ceiling becomes a permanent outage trigger once the master grows past
// it (round-3 L2). Generic outcome wording: which vendor failure it is cannot
// be known from here (round-3 L6).
export function classifySelfChecks(futureResult, anchorResult) {
  if (!futureResult || futureResult.outcome !== "quiet") {
    return { outcome: "self-check-failed", message: `the future-dated createdFrom probe must be empty but returned ${JSON.stringify(futureResult?.newItems ?? futureResult)} — the filter is being ignored or the response is unreadable` };
  }
  if (anchorResult === undefined) return { outcome: "ok", anchorChecked: false };
  if (anchorResult.outcome !== "trigger" || !Number.isFinite(anchorResult.newItems) || anchorResult.newItems <= 0) {
    return { outcome: "self-check-failed", message: `the old-dated createdFrom probe must return a non-empty count but gave ${JSON.stringify(anchorResult?.newItems ?? anchorResult)} — the filter is being silently rejected or misread` };
  }
  return { outcome: "ok", anchorChecked: true, anchorCount: anchorResult.newItems };
}

async function main() {
  const apiKey = readColdlionApiKey();
  const urls = buildHeartbeatUrls();
  // The window and future probes use the trigger threshold (a huge match there
  // means an ignored filter). The anchor probe EXPECTS a huge match — its job
  // is only non-emptiness — so it is classified with no ceiling (round-3 B1:
  // classifying it with the window threshold made every run exit 1).
  const thresholds = {
    window: {},
    futureEmpty: {},
    anchorNonEmpty: { maxNewItems: Number.MAX_SAFE_INTEGER },
  };
  const results = {};
  for (const [kind, url] of Object.entries(urls)) {
    const response = await fetch(url, { headers: { "X-API-Key": apiKey }, signal: AbortSignal.timeout(HEARTBEAT_FETCH_TIMEOUT_MS) });
    if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
    results[kind] = { url: String(url), ...classifyHeartbeat(await response.json(), thresholds[kind]) };
  }
  const selfCheck = classifySelfChecks(results.futureEmpty, results.anchorNonEmpty);
  const trigger = results.window.outcome === "trigger";
  const bad = selfCheck.outcome !== "ok" || results.window.outcome !== "quiet" && results.window.outcome !== "trigger";
  process.stdout.write(`${JSON.stringify({ checkedAt: new Date().toISOString(), trigger, selfCheck, window: results.window }, null, 2)}\n`);
  if (bad) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`Coldlion item heartbeat failed: ${error.stack ?? error}\n`);
    process.exitCode = 1;
  });
}
