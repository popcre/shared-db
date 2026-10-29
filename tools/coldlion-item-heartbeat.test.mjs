import test from "node:test";
import assert from "node:assert/strict";

import {
  HEARTBEAT_ANCHOR_DATE,
  HEARTBEAT_MAX_NEW_ITEMS,
  HEARTBEAT_WINDOW_MINUTES,
  buildHeartbeatUrls,
  classifyHeartbeat,
  classifySelfChecks,
} from "./coldlion-item-heartbeat.mjs";

test("three tiny GETs: the window, a must-be-empty future, a must-be-non-empty anchor", () => {
  const now = new Date("2026-10-29T12:00:00.000Z");
  const urls = buildHeartbeatUrls({ now, baseUrl: "https://coldlion.example", windowMinutes: 6 });
  assert.equal(String(urls.window), `https://coldlion.example/items?companyCode=EDGEHOME&createdFrom=2026-10-29T11%3A54%3A00.000Z&size=1&page=0`);
  assert.equal(String(urls.futureEmpty), "https://coldlion.example/items?companyCode=EDGEHOME&createdFrom=2026-10-30T12%3A00%3A00.000Z&size=1&page=0");
  assert.equal(String(urls.oldNonEmpty), `https://coldlion.example/items?companyCode=EDGEHOME&createdFrom=${encodeURIComponent(HEARTBEAT_ANCHOR_DATE)}&size=1&page=0`);
  assert.equal(HEARTBEAT_WINDOW_MINUTES, 6, "the window just overlaps the 5-minute cadence");
});

test("quiet when nothing matched; trigger with the sample item number when something did", () => {
  assert.deepEqual(classifyHeartbeat({ content: [], totalElements: 0 }), { outcome: "quiet", newItems: 0 });
  const triggered = classifyHeartbeat({ content: [{ itemNo: " A1 " }], totalElements: 3, last: false });
  assert.equal(triggered.outcome, "trigger");
  assert.equal(triggered.newItems, 3);
  assert.deepEqual(triggered.itemNumbers, ["A1"]);
});

test("an ignored filter is caught by totalElements even though the page holds one row (review H1/B1)", () => {
  const wholeMaster = classifyHeartbeat({ content: [{ itemNo: "X1" }], totalElements: 19_862, totalPages: 19_862 });
  assert.equal(wholeMaster.outcome, "filter-suspected");
  assert.match(wholeMaster.message, /filter appears ignored/);
  const bulk = classifyHeartbeat({ content: [{ itemNo: "B1" }], totalElements: 320 });
  assert.equal(bulk.outcome, "trigger", "a legitimate bulk creation under the threshold still triggers one sweep");
  const bare = classifyHeartbeat(Array.from({ length: HEARTBEAT_MAX_NEW_ITEMS + 1 }, (_, index) => ({ itemNo: `Y${index}` })));
  assert.equal(bare.outcome, "filter-suspected");
});

test("an envelope without totalElements is a shape change, never a silent fallback (review L1)", () => {
  const noTotal = classifyHeartbeat({ content: [{ itemNo: "A1" }], last: true });
  assert.equal(noTotal.outcome, "malformed");
  assert.match(noTotal.message, /no totalElements/);
  const notAnEnvelope = classifyHeartbeat({ not: "an envelope" });
  assert.equal(notAnEnvelope.outcome, "malformed");
});

test("self-checks: a non-empty future or an empty/insane anchor fails loudly (review B2)", () => {
  const ok = classifySelfChecks({ outcome: "quiet", newItems: 0 }, { outcome: "trigger", newItems: 15_868 });
  assert.equal(ok.outcome, "ok");
  const futureNonEmpty = classifySelfChecks({ outcome: "trigger", newItems: 4 }, { outcome: "trigger", newItems: 15_868 });
  assert.equal(futureNonEmpty.outcome, "filter-suspected");
  assert.match(futureNonEmpty.message, /future-dated/);
  const anchorEmpty = classifySelfChecks({ outcome: "quiet", newItems: 0 }, { outcome: "quiet", newItems: 0 });
  assert.equal(anchorEmpty.outcome, "malformed");
  assert.match(anchorEmpty.message, /old-dated/);
  const anchorInsane = classifySelfChecks({ outcome: "quiet", newItems: 0 }, { outcome: "trigger", newItems: 99_999_999 });
  assert.equal(anchorInsane.outcome, "malformed");
});
