import test from "node:test";
import assert from "node:assert/strict";

import {
  HEARTBEAT_MAX_NEW_ITEMS,
  HEARTBEAT_WINDOW_MINUTES,
  buildHeartbeatUrls,
  classifyHeartbeat,
} from "./coldlion-item-heartbeat.mjs";

test("the probe asks two filtered questions: created and modified since the window", () => {
  const now = new Date("2026-10-29T12:00:00.000Z");
  const urls = buildHeartbeatUrls({ now, baseUrl: "https://coldlion.example", windowMinutes: 15 });
  assert.equal(String(urls.created), "https://coldlion.example/items?companyCode=EDGEHOME&createdFrom=2026-10-29T11%3A45%3A00.000Z&size=50&page=0");
  assert.equal(String(urls.modified), "https://coldlion.example/items?companyCode=EDGEHOME&modifiedFrom=2026-10-29T11%3A45%3A00.000Z&size=50&page=0");
  assert.equal(HEARTBEAT_WINDOW_MINUTES, 15, "the window must overlap the 5-minute cadence");
});

test("quiet when nothing matched; trigger with the on-page item numbers when something did", () => {
  assert.deepEqual(classifyHeartbeat({ content: [], totalElements: 0 }), { outcome: "quiet", newItems: 0 });
  assert.deepEqual(classifyHeartbeat([]), { outcome: "quiet", newItems: 0 });
  const triggered = classifyHeartbeat({ content: [{ itemNo: " A1 " }, { itemNo: "A2" }], totalElements: 2 });
  assert.equal(triggered.outcome, "trigger");
  assert.deepEqual(triggered.itemNumbers, ["A1", "A2"]);
});

test("an ignored filter is caught by totalElements even when the page itself is capped (review H1)", () => {
  const pageCapped = { content: Array.from({ length: 50 }, (_, index) => ({ itemNo: `X${index}` })), totalElements: 19_840, totalPages: 397, last: false };
  const suspected = classifyHeartbeat(pageCapped);
  assert.equal(suspected.outcome, "filter-suspected");
  assert.match(suspected.message, /19 ?840|filter appears ignored/);
  // A legitimate bulk creation under the threshold still triggers exactly one sweep.
  const bulk = classifyHeartbeat({ content: Array.from({ length: 50 }, (_, index) => ({ itemNo: `B${index}` })), totalElements: 320, totalPages: 7, last: false });
  assert.equal(bulk.outcome, "trigger");
  assert.equal(bulk.newItems, 320);
  // No envelope metadata: fall back to the row count.
  const bare = classifyHeartbeat({ content: Array.from({ length: HEARTBEAT_MAX_NEW_ITEMS + 1 }, (_, index) => ({ itemNo: `Y${index}` })) });
  assert.equal(bare.outcome, "filter-suspected");
});

test("a vendor shape change is malformed, never a green blind heartbeat (review M1)", () => {
  const malformed = classifyHeartbeat({ not: "an envelope" });
  assert.equal(malformed.outcome, "malformed");
  assert.match(malformed.message, /neither an array nor a paged content envelope/);
});
