import test from "node:test";
import assert from "node:assert/strict";

import {
  HEARTBEAT_MAX_NEW_ITEMS,
  HEARTBEAT_WINDOW_MINUTES,
  buildHeartbeatUrl,
  classifyHeartbeat,
} from "./coldlion-item-heartbeat.mjs";

test("the probe asks one filtered question: anything created since the window?", () => {
  const now = new Date("2026-10-29T12:00:00.000Z");
  const url = buildHeartbeatUrl({ now, baseUrl: "https://coldlion.example", windowMinutes: 15 });
  assert.equal(String(url), "https://coldlion.example/items?companyCode=EDGEHOME&createdFrom=2026-10-29T11%3A45%3A00.000Z&size=50&page=0");
  assert.equal(HEARTBEAT_WINDOW_MINUTES, 15, "the window must overlap the 5-minute cadence");
});

test("quiet when nothing is new; trigger with the item numbers when something is", () => {
  assert.deepEqual(classifyHeartbeat({ content: [] }), { outcome: "quiet", newItems: 0 });
  assert.deepEqual(classifyHeartbeat([]), { outcome: "quiet", newItems: 0 });
  const triggered = classifyHeartbeat({ content: [{ itemNo: " A1 " }, { itemNo: "A2" }] });
  assert.equal(triggered.outcome, "trigger");
  assert.deepEqual(triggered.itemNumbers, ["A1", "A2"]);
});

test("a vendor surprise fails loudly: ignored filter, malformed body", () => {
  const suspected = classifyHeartbeat({ content: Array.from({ length: HEARTBEAT_MAX_NEW_ITEMS + 1 }, (_, index) => ({ itemNo: `X${index}` })) });
  assert.equal(suspected.outcome, "filter-suspected");
  assert.match(suspected.message, /filter appears ignored/);
  const malformed = classifyHeartbeat({ not: "an envelope" });
  assert.equal(malformed.outcome, "malformed");
});
