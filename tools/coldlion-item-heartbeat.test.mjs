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

test("the window and future probes run every cycle; the anchor once per half-hour", () => {
  const now = new Date("2026-10-29T12:07:00.000Z");
  const urls = buildHeartbeatUrls({ now, baseUrl: "https://coldlion.example", windowMinutes: 6 });
  assert.equal(String(urls.window), `https://coldlion.example/items?companyCode=EDGEHOME&createdFrom=2026-10-29T12%3A01%3A00.000Z&size=1&page=0`);
  assert.ok(urls.futureEmpty, "the future self-check runs every cycle");
  assert.ok(urls.anchorNonEmpty, "the anchor self-check IS due at :07 (first 10 minutes of the half-hour cover cron jitter)");
  const betweenAnchors = buildHeartbeatUrls({ now: new Date("2026-10-29T12:22:00.000Z"), baseUrl: "https://coldlion.example" });
  assert.equal(betweenAnchors.anchorNonEmpty, undefined, "the anchor self-check is not due at :22");
  const onTheHalfHour = buildHeartbeatUrls({ now: new Date("2026-10-29T12:32:00.000Z"), baseUrl: "https://coldlion.example" });
  assert.ok(onTheHalfHour.anchorNonEmpty, "the anchor self-check is due at :32");
  assert.equal(HEARTBEAT_WINDOW_MINUTES, 6, "the window just overlaps the 5-minute cadence");
});

test("quiet when nothing matched; trigger with the sample item number when something did", () => {
  assert.deepEqual(classifyHeartbeat({ content: [], totalElements: 0 }), { outcome: "quiet", newItems: 0 });
  const triggered = classifyHeartbeat({ content: [{ itemNo: " A1 " }], totalElements: 3, last: false });
  assert.equal(triggered.outcome, "trigger");
  assert.equal(triggered.newItems, 3);
  assert.deepEqual(triggered.itemNumbers, ["A1"]);
});

test("an ignored filter is caught by totalElements even though the page holds one row", () => {
  const wholeMaster = classifyHeartbeat({ content: [{ itemNo: "X1" }], totalElements: 19_862, totalPages: 19_862 });
  assert.equal(wholeMaster.outcome, "filter-suspected");
  const bulk = classifyHeartbeat({ content: [{ itemNo: "B1" }], totalElements: 320 });
  assert.equal(bulk.outcome, "trigger", "a legitimate bulk creation under the threshold still triggers one sweep");
});

test("a bare array or envelope without totalElements is a shape change, never a fallback", () => {
  assert.equal(classifyHeartbeat([{ itemNo: "A1" }]).outcome, "malformed");
  assert.equal(classifyHeartbeat({ content: [{ itemNo: "A1" }], last: true }).outcome, "malformed");
  assert.equal(classifyHeartbeat({ not: "an envelope" }).outcome, "malformed");
});

// The chained test round 3 demanded (H1): the RECORDED live payloads, through
// BOTH classifiers exactly as main() wires them — this is the path that would
// have caught round-3 B1 (the anchor's 15,868 wrongly hitting the window
// threshold).
test("the recorded live payloads chain cleanly through both classifiers (round-3 B1/H1)", () => {
  const recorded = {
    window: { content: [], totalElements: 0 },
    future: { content: [], totalElements: 0 },
    anchor: { content: [{ itemNo: "BRG62NBSF03" }], totalElements: 15_868, totalPages: 15_868 },
  };
  const windowResult = classifyHeartbeat(recorded.window);
  const futureResult = classifyHeartbeat(recorded.future);
  // Exactly the wiring main() uses: the anchor is classified with NO ceiling.
  const anchorResult = classifyHeartbeat(recorded.anchor, { maxNewItems: Number.MAX_SAFE_INTEGER });
  assert.equal(windowResult.outcome, "quiet");
  assert.equal(futureResult.outcome, "quiet");
  assert.equal(anchorResult.outcome, "trigger");
  assert.equal(anchorResult.newItems, 15_868);
  // The round-3 B1 trap, kept as a guard: with the WINDOW threshold the anchor
  // is filter-suspected, and feeding that to the self-check fails the run.
  const misclassified = classifyHeartbeat(recorded.anchor);
  assert.equal(misclassified.outcome, "filter-suspected");
  assert.equal(classifySelfChecks(futureResult, misclassified).outcome, "self-check-failed");
  assert.equal(classifySelfChecks(futureResult, anchorResult).outcome, "ok");
});

test("self-checks judge the anchor by non-emptiness only, with generic wording", () => {
  assert.equal(classifySelfChecks({ outcome: "quiet", newItems: 0 }, undefined).outcome, "ok");
  assert.equal(classifySelfChecks({ outcome: "quiet", newItems: 0 }, { outcome: "trigger", newItems: 99_999_999 }).outcome, "ok", "no fixed ceiling: a grown master must not trip an outage (L2)");
  const futureNonEmpty = classifySelfChecks({ outcome: "trigger", newItems: 4 }, { outcome: "trigger", newItems: 15_868 });
  assert.equal(futureNonEmpty.outcome, "self-check-failed");
  assert.match(futureNonEmpty.message, /future-dated/);
  assert.ok(!/ignored/.test(futureNonEmpty.message) || /ignored or/.test(futureNonEmpty.message), "wording does not claim a specific vendor failure (L6)");
  const anchorEmpty = classifySelfChecks({ outcome: "quiet", newItems: 0 }, { outcome: "quiet", newItems: 0 });
  assert.equal(anchorEmpty.outcome, "self-check-failed");
  assert.match(anchorEmpty.message, /old-dated/);
});
