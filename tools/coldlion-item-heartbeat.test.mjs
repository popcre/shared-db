import test from "node:test";
import assert from "node:assert/strict";

import {
  HEARTBEAT_WINDOW_MINUTES,
  buildHeartbeatUrl,
  classifyHeartbeat,
  vendorTimeToUtc,
} from "./coldlion-item-heartbeat.mjs";

// The recorded live envelope for sort=createdTime,desc (issue #5011, 2026-10-29).
const RECORDED = {
  totalElements: 19_862,
  sort: [{ direction: "DESC", property: "createdTime", ignoreCase: false, nullHandling: "NATIVE", ascending: false, descending: true }],
  content: [{ itemNo: "NKR82HDWAN02", createdTime: "2026-10-28 17:27:39.668", modTime: "2026-10-28 17:27:39.668" }],
};

test("one GET: newest item first", () => {
  assert.equal(String(buildHeartbeatUrl({ baseUrl: "https://coldlion.example" })), "https://coldlion.example/items?companyCode=EDGEHOME&sort=createdTime%2Cdesc&size=1&page=0");
  assert.equal(HEARTBEAT_WINDOW_MINUTES, 6, "the window just overlaps the 5-minute cadence");
});

test("vendor wall time is America/New_York (recorded correlation evidence)", () => {
  assert.equal(vendorTimeToUtc("2026-10-28 17:27:39.668").toISOString().slice(0, 16), "2026-10-28T21:27", "EDT = UTC-4 on the recorded date");
  assert.equal(vendorTimeToUtc("2026-01-15 09:00:00").toISOString().slice(0, 16), "2026-01-15T14:00", "EST = UTC-5 in winter");
  assert.equal(vendorTimeToUtc("not a time"), null);
  assert.equal(vendorTimeToUtc(undefined), null);
});

test("the recorded newest item triggers only inside the window", () => {
  const trigger = classifyHeartbeat(RECORDED, { now: new Date("2026-10-28T21:30:00.000Z") });
  assert.equal(trigger.outcome, "trigger");
  assert.deepEqual(trigger.itemNumbers, ["NKR82HDWAN02"]);
  const quiet = classifyHeartbeat(RECORDED, { now: new Date("2026-10-28T23:30:00.000Z") });
  assert.equal(quiet.outcome, "quiet");
  assert.ok(quiet.ageMinutes > 100);
});

test("a vendor sort change fails loudly — the recorded unsorted default echo", () => {
  const unsorted = { ...RECORDED, sort: [{ direction: "ASC", property: "ItemNo", ignoreCase: false, nullHandling: "NATIVE", ascending: true, descending: false }], content: [{ itemNo: "01", createdTime: "2022-07-21 13:38:41.992" }] };
  const result = classifyHeartbeat(unsorted, { now: new Date("2026-10-29T04:00:00.000Z") });
  assert.equal(result.outcome, "malformed");
  assert.match(result.message, /sort echo/);
});

test("shape failures are loud, never a quiet pass", () => {
  assert.equal(classifyHeartbeat([{ itemNo: "A1" }]).outcome, "malformed");
  assert.equal(classifyHeartbeat({ content: [{ itemNo: "A1" }] }).outcome, "malformed");
  const noTime = classifyHeartbeat({ ...RECORDED, content: [{ itemNo: "X1", createdTime: null }] });
  assert.equal(noTime.outcome, "malformed");
  assert.match(noTime.message, /parseable createdTime/);
  const empty = classifyHeartbeat({ ...RECORDED, totalElements: 0, content: [] });
  assert.equal(empty.outcome, "malformed");
  assert.match(empty.message, /empty/);
  const future = classifyHeartbeat(RECORDED, { now: new Date("2026-10-28T12:00:00.000Z") });
  assert.equal(future.outcome, "malformed");
  assert.match(future.message, /timezone contract/);
});
