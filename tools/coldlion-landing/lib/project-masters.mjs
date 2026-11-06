import { date, num, sourceHash, text } from "./values.mjs";
import { knownApiFields } from "./master-specs.mjs";

function timestamp(value) {
  const raw = text(value);
  if (raw === null) return null;
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.valueOf())) throw new Error("a timestamp field was not an ISO timestamp");
  if (parsed.toISOString() <= "1900-01-01T23:59:59.999Z") return null;
  return parsed.toISOString();
}

// The merchGroupNNDesc family is not item data (#5758 D4, 2026-11-05): the same
// /items and /itemDetails snapshot returns the same merchGroupNN code with the
// description valued on one night and null on the next, so a hash that includes
// them logs ~10k non-change rows per night. Descriptions of a merch-group CODE
// live on coldlion.merch_group_detail; item rows and their hashes carry codes
// only. The raw payloads (source_raw / change_log) still keep whatever arrived.
const SLOT_DESC_KEY = /^merchGroup\d\dDesc$/;

export function stripSlotDescFields(source) {
  const stripped = {};
  for (const [key, value] of Object.entries(source)) {
    if (SLOT_DESC_KEY.test(key)) continue;
    stripped[key] = value;
  }
  return stripped;
}

const converters = { text, num, date, ts: timestamp };
converters.keytext = (value) => value === null || value === undefined ? null : String(value).trim();

export function assertKnownShape(spec, rows) {
  const known = knownApiFields(spec);
  const unknown = [...new Set(rows.flatMap((row) => Object.keys(row)).filter((key) => !known.has(key)))].sort();
  if (unknown.length) throw new Error(`${spec.endpoint} returned unreviewed field(s): ${unknown.join(", ")}`);
  const required = spec.fields.map((field)=>field.api);
  for (const row of rows) {
    const missing=required.filter((field)=>!(field in row));
    if (missing.length) throw new Error(`${spec.endpoint} omitted approved field(s): ${missing.join(", ")}`);
  }
}

export function projectCurrentRows(spec, sourceRows, { runId, fetchedAt, excludeDivision = "EP001" } = {}) {
  try { assertKnownShape(spec, sourceRows); }
  catch (error) { error.endpoint ??= spec.endpoint; throw error; }
  const byKey = new Map();
  let excluded = 0;
  for (const source of sourceRows) {
    if (text(source.divisionCode) === excludeDivision) { excluded += 1; continue; }
    const row = {};
    for (const field of spec.fields) row[field.column] = converters[field.type](source[field.api]);
    // The schema contract requires a complete-record hash and retains that record
    // privately in change_log; public fixtures and logs never contain its values.
    // Slot-bearing feeds hash the record with the merchGroupNNDesc family removed
    // (#5758): those fields flap between valued and blank on identical snapshots,
    // and a description is resolved by joining merch_group_detail on the code, so
    // it must never decide whether an item row "changed".
    row.source_hash = sourceHash(spec.slots ? stripSlotDescFields(source) : source);
    row.source_raw = source;
    row.run_id = runId;
    row.fetched_at = fetchedAt;
    const key = spec.key.map((column) => row[column] ?? "").join("\u001f");
    if (spec.key.some((column) => row[column] === null)) { const error=new Error(`${spec.endpoint} returned a blank natural key`); error.endpoint=spec.endpoint; throw error; }
    const prior = byKey.get(key);
    if (prior) { const error=new Error(`${spec.endpoint} returned duplicate rows for one natural key`); error.endpoint=spec.endpoint; throw error; }
    byKey.set(key, row);
  }
  return { rows: [...byKey.values()], excluded };
}

export function projectItemSlots(sourceRows, { runId, fetchedAt, itemPkey = null, excludeDivision = "EP001" } = {}) {
  const slots = [];
  for (const source of sourceRows) {
    if (text(source.divisionCode) === excludeDivision) continue;
    for (let slotNo = 1; slotNo <= 14; slotNo += 1) {
      const suffix = String(slotNo).padStart(2, "0");
      const mgCode = text(source[`merchGroup${suffix}`]);
      if (mgCode === null) continue;
      const row = {
        company_code: text(source.companyCode), division_code: text(source.divisionCode), item_no: text(source.itemNo),
        item_pkey: itemPkey === "source" ? text(source.itemPkey) : null,
        slot_no: slotNo, mg_code: mgCode,
        run_id: runId, fetched_at: fetchedAt,
      };
      // Codes only (#5758 D4): the slot IS (slotNo, mgCode). The description of
      // that code belongs to coldlion.merch_group_detail and is joined when a
      // reader wants a label; hashing it here recorded the vendor's intermittent
      // omission of merchGroupNNDesc as a nightly "change" for ~90% of the log.
      row.source_hash = sourceHash({ slotNo, mgCode: row.mg_code });
      slots.push(row);
    }
  }
  return slots;
}
