#!/usr/bin/env node

// #5011: the new-item heartbeat. ONE tiny GET every 5 minutes asks ColdLion
// for the single newest item (/items?sort=createdTime,desc&size=1) and
// dispatches the existing item sweep when that item was created inside the
// window — replacing the old 30-minute full sweep.
//
// RECORDED LIVE EVIDENCE (2026-10-29, read-only, production ColdLion, issue
// #5011; "record the probe or it is fabricated"):
//   - createdFrom is DAY-TYPED: instants 2026-10-28T00:00:01Z,
//     2026-10-28T23:59:59Z and the bare date 2026-10-28 ALL return
//     totalElements=41 — the vendor truncates to the date, so a 6-minute
//     createdFrom window cannot work (round-4 blocking finding, confirmed).
//   - sort works and is ECHOED: sort=createdTime,desc returns the newest item
//     first and the envelope echoes
//     sortField=[{direction:"DESC",property:"createdTime"}]; the unsorted
//     default echoes property "ItemNo" ASC. The probe asserts the echo, so a
//     vendor change that drops sort support fails loudly instead of quietly
//     watching an old item.
//   - Vendor createdTime is America/New_York wall time, not UTC: on 2026-10-28
//     the items AA020NDCST02 (17:09) and NKR82HDWAN02 (17:27) landed in
//     plm.item at 21:54 UTC — exactly one sweep cycle after 17:09/17:27 EDT
//     (= 21:09/21:27 UTC), and hours off under any UTC reading. The probe
//     converts vendor wall time through the America/New_York offset.
//   - modifiedFrom serves createdFrom semantics (identical totals on every
//     probe) — no edit-coverage probe is possible; item edits land at the
//     three anchor sweeps plus the nightly masters run (trade-off on #5011).

import { pathToFileURL } from "node:url";
import { COLDLION_BASE_URL, readColdlionApiKey } from "./coldlion-sync-common.mjs";

// Just over the 5-minute cadence: a delayed or skipped run still sees the next
// run's window, while a single creation triggers at most one extra dispatch
// (the workflow additionally throttles dispatches to one sweep per 10 minutes).
export const HEARTBEAT_WINDOW_MINUTES = 6;
export const HEARTBEAT_FETCH_TIMEOUT_MS = 10_000;

export function buildHeartbeatUrl({ baseUrl = COLDLION_BASE_URL } = {}) {
  const url = new URL(`${baseUrl}/items`);
  url.searchParams.set("companyCode", "EDGEHOME");
  url.searchParams.set("sort", "createdTime,desc");
  url.searchParams.set("size", "1");
  url.searchParams.set("page", "0");
  return url;
}

// Vendor wall time ("2026-10-28 17:27:39.668") is America/New_York; convert
// through the zone offset valid at that wall time. Called only on timestamps
// at most hours old, so a DST transition mid-window is impossible in practice;
// a wrong or unparseable timestamp is a shape failure, never a quiet pass.
export function vendorTimeToUtc(value, { zone = "America/New_York" } = {}) {
  const match = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?$/.exec(String(value ?? "").trim());
  if (!match) return null;
  const [, year, month, day, hour, minute, second, fraction] = match;
  const wallAsUtc = Date.UTC(Number(year), Number(month) - 1, Number(day), Number(hour), Number(minute), Number(second), Number((fraction ?? "0").padEnd(3, "0").slice(0, 3)));
  const dtf = new Intl.DateTimeFormat("en-US", { timeZone: zone, hour12: false, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" });
  const zoneOffsetFor = (instant) => {
    const parts = Object.fromEntries(dtf.formatToParts(new Date(instant)).map((part) => [part.type, part.value]));
    return Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day), Number(parts.hour) % 24, Number(parts.minute), Number(parts.second)) - instant;
  };
  const firstGuess = wallAsUtc - zoneOffsetFor(wallAsUtc);
  return new Date(wallAsUtc - zoneOffsetFor(firstGuess));
}

// The recorded shapes, judged strictly: a paged envelope whose sort echo says
// createdTime DESC, a finite totalElements, and a parseable newest-row
// createdTime. Anything else is a vendor shape change and fails loudly.
export function classifyHeartbeat(payload, { now = new Date(), windowMinutes = HEARTBEAT_WINDOW_MINUTES } = {}) {
  const rows = payload?.content;
  if (!Array.isArray(rows) || !Number.isFinite(payload?.totalElements)) {
    return { outcome: "malformed", message: "response is not a paged envelope with content and totalElements" };
  }
  const sortEcho = Array.isArray(payload?.sort) ? payload.sort : [];
  const isCreatedTimeDesc = sortEcho.some((entry) => String(entry?.property) === "createdTime" && String(entry?.direction).toUpperCase() === "DESC");
  if (!isCreatedTimeDesc) {
    return { outcome: "malformed", message: `the sort echo does not say createdTime DESC (${JSON.stringify(sortEcho)}) — the newest-item contract is broken; refusing to judge an arbitrary first row` };
  }
  if (!rows.length) return { outcome: "malformed", message: "the item master is empty — the newest-item contract is broken" };
  const newest = rows[0];
  const createdUtc = vendorTimeToUtc(newest?.createdTime);
  if (!createdUtc) {
    return { outcome: "malformed", message: `the newest row carries no parseable createdTime (${JSON.stringify(newest?.createdTime)})` };
  }
  const ageMinutes = (now.getTime() - createdUtc.getTime()) / 60_000;
  if (!Number.isFinite(ageMinutes) || ageMinutes < -windowMinutes) {
    return { outcome: "malformed", message: `the newest createdTime resolves ${ageMinutes} minutes from now — the timezone contract is broken` };
  }
  if (ageMinutes <= windowMinutes) {
    return { outcome: "trigger", newItems: 1, itemNumbers: [String(newest?.itemNo ?? "").trim()].filter(Boolean), newestCreatedUtc: createdUtc.toISOString(), ageMinutes: Math.round(ageMinutes * 10) / 10 };
  }
  return { outcome: "quiet", newItems: 0, newestCreatedUtc: createdUtc.toISOString(), ageMinutes: Math.round(ageMinutes * 10) / 10 };
}

async function main() {
  const apiKey = readColdlionApiKey();
  const url = buildHeartbeatUrl();
  const response = await fetch(url, { headers: { "X-API-Key": apiKey }, signal: AbortSignal.timeout(HEARTBEAT_FETCH_TIMEOUT_MS) });
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
  const result = classifyHeartbeat(await response.json());
  process.stdout.write(`${JSON.stringify({ url: String(url), checkedAt: new Date().toISOString(), ...result }, null, 2)}\n`);
  if (result.outcome === "malformed") process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`Coldlion item heartbeat failed: ${error.stack ?? error}\n`);
    process.exitCode = 1;
  });
}
